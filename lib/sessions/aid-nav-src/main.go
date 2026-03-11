// aid-nav — left-pane session navigator for aid --mode orchestrator.
//
// Discovers all aid@* orchestrator tmux sessions, queries each session's
// opencode HTTP API for conversations, and renders a tree-style TUI.
//
// Keybindings:
//
//	j / ↓       navigate down
//	k / ↑       navigate up
//	Enter       select (switch tmux session or switch conversation)
//	n           new orchestrator session from cwd
//	d           delete selected session (with confirmation)
//	r           rename selected session (not yet implemented)
//	q / Ctrl+C  quit
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Styles ─────────────────────────────────────────────────────────────────────

var (
	styleFocused = lipgloss.NewStyle().Foreground(lipgloss.Color("12")).Bold(true)
	styleSession = lipgloss.NewStyle().Foreground(lipgloss.Color("6")).Bold(true)
	styleConv    = lipgloss.NewStyle().Foreground(lipgloss.Color("7"))
	styleConvDim = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	styleCursor  = lipgloss.NewStyle().Background(lipgloss.Color("0")).Foreground(lipgloss.Color("15")).Bold(true)
	styleHelp    = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	styleErr     = lipgloss.NewStyle().Foreground(lipgloss.Color("9"))
	styleConfirm = lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Bold(true)
)

// ── Data types ──────────────────────────────────────────────────────────────────

// orcSession is one aid@<name> tmux session with its opencode port.
type orcSession struct {
	tmuxName  string // e.g. "aid@myproject"
	shortName string // e.g. "myproject"
	port      int
	convs     []conversation
	err       error
}

// conversation is one opencode session (conversation) from GET /session.
type conversation struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Directory string `json:"directory"`
	Time      struct {
		Updated int64 `json:"updated"`
		Created int64 `json:"created"`
	} `json:"time"`
}

// flatItem is a rendered row in the list (either a session header or a conv).
type flatItem struct {
	sessionIdx int // index into model.sessions
	convIdx    int // -1 if this is the session header
}

// ── Model ───────────────────────────────────────────────────────────────────────

type model struct {
	sessions  []orcSession
	flat      []flatItem // flattened for cursor navigation
	cursor    int
	width     int
	height    int
	lastFetch time.Time
	fetchErr  string

	// confirmation state for delete
	confirming  bool
	confirmText string
	confirmYes  func() tea.Cmd

	// aid dir from env (to call orchestrator.sh --new)
	aidDir string
}

func initialModel() model {
	return model{
		aidDir: os.Getenv("AID_DIR"),
		width:  40,
		height: 24,
	}
}

// ── Messages ───────────────────────────────────────────────────────────────────

type fetchDoneMsg struct {
	sessions []orcSession
	err      string
}

type tickMsg time.Time

type switchedMsg struct{}

type newSessionMsg struct{}

type deleteSessionMsg struct{}

// ── Init ────────────────────────────────────────────────────────────────────────

func (m model) Init() tea.Cmd {
	return tea.Batch(fetchSessions(), tickEvery(2*time.Second))
}

// ── Update ──────────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tickMsg:
		return m, tea.Batch(fetchSessions(), tickEvery(2*time.Second))

	case fetchDoneMsg:
		m.sessions = msg.sessions
		m.fetchErr = msg.err
		m.flat = buildFlat(m.sessions)
		// clamp cursor
		if m.cursor >= len(m.flat) {
			m.cursor = max(0, len(m.flat)-1)
		}
		return m, nil

	case switchedMsg:
		return m, nil

	case newSessionMsg, deleteSessionMsg:
		// Trigger an immediate re-fetch so the tree updates promptly.
		return m, fetchSessions()

	case tea.KeyMsg:
		if m.confirming {
			return m.handleConfirmKey(msg)
		}
		return m.handleKey(msg)
	}

	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit

	case "j", "down":
		if m.cursor < len(m.flat)-1 {
			m.cursor++
		}

	case "k", "up":
		if m.cursor > 0 {
			m.cursor--
		}

	case "enter":
		if len(m.flat) == 0 {
			break
		}
		item := m.flat[m.cursor]
		sess := m.sessions[item.sessionIdx]
		if item.convIdx == -1 {
			// Session header — switch tmux client to that session.
			return m, switchTmux(sess.tmuxName)
		}
		// Conversation — POST /tui/select-session then switch.
		conv := sess.convs[item.convIdx]
		return m, selectConversation(sess.port, conv.ID, sess.tmuxName)

	case "n":
		// New orchestrator session from cwd.
		return m, newSession(m.aidDir)

	case "d":
		if len(m.flat) == 0 {
			break
		}
		item := m.flat[m.cursor]
		if item.convIdx == -1 {
			sess := m.sessions[item.sessionIdx]
			m.confirming = true
			m.confirmText = fmt.Sprintf("Delete session %s? (y/N)", sess.tmuxName)
			m.confirmYes = func() tea.Cmd {
				return deleteSession(sess.tmuxName)
			}
		}
	}
	return m, nil
}

func (m model) handleConfirmKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	m.confirming = false
	switch msg.String() {
	case "y", "Y":
		cmd := m.confirmYes()
		m.confirmYes = nil
		return m, cmd
	}
	m.confirmYes = nil
	return m, nil
}

// ── View ────────────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.confirming {
		return styleConfirm.Render(m.confirmText) + "\n"
	}

	var sb strings.Builder

	// ── List area ──
	listHeight := m.height - 2 // reserve 2 lines for help bar
	if listHeight < 1 {
		listHeight = 1
	}

	// Scroll window: keep cursor visible.
	start := 0
	if len(m.flat) > listHeight {
		start = m.cursor - listHeight/2
		if start < 0 {
			start = 0
		}
		if start+listHeight > len(m.flat) {
			start = len(m.flat) - listHeight
		}
	}
	end := start + listHeight
	if end > len(m.flat) {
		end = len(m.flat)
	}

	for i := start; i < end; i++ {
		item := m.flat[i]
		sess := m.sessions[item.sessionIdx]
		selected := i == m.cursor

		var line string
		if item.convIdx == -1 {
			// Session header.
			label := " " + sess.tmuxName
			if sess.err != nil {
				label += styleErr.Render(" !")
			}
			if selected {
				line = styleCursor.Width(m.width).Render(label)
			} else {
				line = styleSession.Render(label)
			}
		} else {
			conv := sess.convs[item.convIdx]
			title := conv.Title
			if title == "" {
				title = "(untitled)"
			}
			// Truncate to fit.
			maxW := m.width - 4
			if len([]rune(title)) > maxW && maxW > 3 {
				title = string([]rune(title)[:maxW-1]) + "…"
			}
			label := "   " + title
			if selected {
				line = styleCursor.Width(m.width).Render(label)
			} else if item.convIdx == 0 {
				line = styleFocused.Render(label)
			} else {
				line = styleConvDim.Render(label)
			}
		}
		sb.WriteString(line + "\n")
	}

	// Pad remaining lines.
	for i := end - start; i < listHeight; i++ {
		sb.WriteString("\n")
	}

	// ── Status/help bar ──
	helpStr := styleHelp.Render("j/k ↑↓  Enter select  n new  d del  q quit")
	if m.fetchErr != "" {
		helpStr = styleErr.Render("fetch err: " + m.fetchErr[:min(len(m.fetchErr), 30)])
	}
	sb.WriteString(helpStr + "\n")

	return sb.String()
}

// ── Commands ───────────────────────────────────────────────────────────────────

func tickEvery(d time.Duration) tea.Cmd {
	return tea.Tick(d, func(t time.Time) tea.Msg { return tickMsg(t) })
}

// fetchSessions discovers all aid@* orchestrator sessions via tmux, reads
// their AID_ORC_PORT (from session environment), and queries GET /session.
func fetchSessions() tea.Cmd {
	return func() tea.Msg {
		// Only two fields needed: name + @aid_mode option.
		// AID_ORC_PORT lives in session *environment*, not a tmux option,
		// so we cannot read it via a format string — use show-environment below.
		out, err := exec.Command("tmux", "-L", "aid", "list-sessions",
			"-F", "#{session_name} #{@aid_mode}").Output()
		if err != nil {
			// Server might not be running yet — return empty.
			return fetchDoneMsg{}
		}

		var sessions []orcSession
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			if line == "" {
				continue
			}
			parts := strings.Fields(line)
			if len(parts) < 2 {
				continue
			}
			name, mode := parts[0], parts[1]
			if mode != "orchestrator" {
				continue
			}
			if !strings.HasPrefix(name, "aid@") {
				continue
			}

			// Read port from session environment.
			var port int
			portOut, _ := exec.Command("tmux", "-L", "aid", "show-environment",
				"-t", name, "AID_ORC_PORT").Output()
			fmt.Sscanf(strings.TrimPrefix(strings.TrimSpace(string(portOut)), "AID_ORC_PORT="), "%d", &port)

			sess := orcSession{
				tmuxName:  name,
				shortName: strings.TrimPrefix(name, "aid@"),
				port:      port,
			}
			if port > 0 {
				sess.convs, sess.err = fetchConvs(port)
			}
			sessions = append(sessions, sess)
		}

		// Sort sessions by tmux name for stable ordering.
		sort.Slice(sessions, func(i, j int) bool {
			return sessions[i].tmuxName < sessions[j].tmuxName
		})

		return fetchDoneMsg{sessions: sessions}
	}
}

// fetchConvs calls GET /session on the given port and returns conversations
// sorted by updated desc.
func fetchConvs(port int) ([]conversation, error) {
	url := fmt.Sprintf("http://127.0.0.1:%d/session", port)
	client := &http.Client{Timeout: 2 * time.Second}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var convs []conversation
	if err := json.Unmarshal(body, &convs); err != nil {
		return nil, err
	}
	// Sort by updated desc.
	sort.Slice(convs, func(i, j int) bool {
		return convs[i].Time.Updated > convs[j].Time.Updated
	})
	return convs, nil
}

// selectConversation POSTs to /tui/select-session then switches tmux client.
func selectConversation(port int, sessionID, tmuxSession string) tea.Cmd {
	return func() tea.Msg {
		url := fmt.Sprintf("http://127.0.0.1:%d/tui/select-session", port)
		body, _ := json.Marshal(map[string]string{"sessionID": sessionID})
		client := &http.Client{Timeout: 2 * time.Second}
		resp, err := client.Post(url, "application/json", bytes.NewReader(body))
		if err == nil {
			resp.Body.Close()
		}
		// Switch tmux regardless of API result.
		_ = exec.Command("tmux", "-L", "aid", "switch-client", "-t", tmuxSession).Run()
		return switchedMsg{}
	}
}

// switchTmux switches the tmux client to the given session.
func switchTmux(tmuxSession string) tea.Cmd {
	return func() tea.Msg {
		_ = exec.Command("tmux", "-L", "aid", "switch-client", "-t", tmuxSession).Run()
		return switchedMsg{}
	}
}

// newSession creates a new orchestrator session from the current working directory.
func newSession(aidDir string) tea.Cmd {
	return func() tea.Msg {
		script := aidDir + "/lib/orchestrator.sh"
		cmd := exec.Command("bash", script, "--new")
		cmd.Stdout = io.Discard
		cmd.Stderr = io.Discard
		_ = cmd.Start()
		return newSessionMsg{}
	}
}

// deleteSession kills the given aid@* tmux session.
func deleteSession(tmuxSession string) tea.Cmd {
	return func() tea.Msg {
		_ = exec.Command("tmux", "-L", "aid", "kill-session", "-t", tmuxSession).Run()
		return deleteSessionMsg{}
	}
}

// ── Helpers ────────────────────────────────────────────────────────────────────

// buildFlat converts sessions into a flat list of items for cursor navigation.
// Each session contributes: one header item, then one item per conversation.
func buildFlat(sessions []orcSession) []flatItem {
	var flat []flatItem
	for si, sess := range sessions {
		flat = append(flat, flatItem{sessionIdx: si, convIdx: -1})
		for ci := range sess.convs {
			flat = append(flat, flatItem{sessionIdx: si, convIdx: ci})
		}
	}
	return flat
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ── Main ────────────────────────────────────────────────────────────────────────

func main() {
	p := tea.NewProgram(
		initialModel(),
		tea.WithAltScreen(),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "aid-nav:", err)
		os.Exit(1)
	}
}
