// Package ui é a interface de terminal do app.
package ui

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/dugonski/macro-app/internal/macro"
)

var (
	accent  = lipgloss.Color("#E8915A")
	cDim    = lipgloss.Color("#8A8A8A")
	cGreen  = lipgloss.Color("#5FBF77")
	cRed    = lipgloss.Color("#E06C75")
	sAccent = lipgloss.NewStyle().Foreground(accent)
	sBold   = lipgloss.NewStyle().Bold(true)
	sDim    = lipgloss.NewStyle().Foreground(cDim)
	sOK     = lipgloss.NewStyle().Foreground(cGreen)
	sFail   = lipgloss.NewStyle().Foreground(cRed)
	sBox    = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(0, 1)
)

type mode int

const (
	modeIdle       mode = iota // esperando um comando
	modeCollecting             // recebendo a lista de itens da macro
	modeRunning                // macro em execução
)

type command struct {
	name, desc string
	macro      *macro.Macro
}

type (
	runEventMsg macro.Event
	runDoneMsg  struct{ err error }
)

type model struct {
	version  string
	simulate bool
	commands []command
	input    textinput.Model
	spin     spinner.Model
	width    int

	mode     mode
	selected int // sugestão destacada
	active   *macro.Macro
	items    []string
	lastKey  time.Time

	events   chan tea.Msg
	cancel   context.CancelFunc
	current  macro.Event
	okCount  int
	failures []macro.Event
}

// Run abre o terminal do app e só retorna quando o usuário sai.
func Run(version string, simulate bool) error {
	m := model{version: version, simulate: simulate, width: 80}
	for _, mc := range macro.All() {
		m.commands = append(m.commands, command{mc.Command, mc.Description, &mc})
	}
	m.commands = append(m.commands,
		command{name: "ajuda", desc: "Mostra os comandos disponíveis"},
		command{name: "limpar", desc: "Limpa a tela"},
		command{name: "sair", desc: "Fecha o app"},
	)

	m.input = textinput.New()
	m.input.Prompt = "> "
	m.input.PromptStyle = sAccent
	m.input.Focus()
	m.spin = spinner.New(spinner.WithSpinner(spinner.Line), spinner.WithStyle(sAccent))

	_, err := tea.NewProgram(m).Run()
	return err
}

func (m model) Init() tea.Cmd {
	return tea.Batch(tea.SetWindowTitle("Macro App"), textinput.Blink, m.banner())
}

func (m model) banner() tea.Cmd {
	title := sAccent.Bold(true).Render("* Macro App") + sDim.Render("  v"+m.version)
	if m.simulate {
		title += sFail.Render("  [simulação]")
	}
	body := title + "\n" + sDim.Render("Digite / para ver os comandos · /ajuda para ajuda")
	return tea.Println(sBox.BorderForeground(accent).Render(body) + "\n")
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.input.Width = max(10, m.width-8)
		return m, nil

	case spinner.TickMsg:
		if m.mode != modeRunning {
			return m, nil
		}
		var cmd tea.Cmd
		m.spin, cmd = m.spin.Update(msg)
		return m, cmd

	case runEventMsg:
		return m.onEvent(macro.Event(msg))

	case runDoneMsg:
		return m.onDone(msg.err)

	case tea.KeyMsg:
		previous := m.lastKey
		m.lastKey = time.Now()
		if msg.Type == tea.KeyCtrlC {
			if m.cancel != nil {
				m.cancel()
			}
			return m, tea.Quit
		}
		switch m.mode {
		case modeRunning:
			if msg.Type == tea.KeyEsc && m.cancel != nil {
				m.cancel()
			}
			return m, nil
		case modeCollecting:
			return m.updateCollecting(msg, previous)
		default:
			return m.updateIdle(msg)
		}
	}
	return m, nil
}

// ---- modo comando ----

func (m model) suggestions() []command {
	text := m.input.Value()
	if !strings.HasPrefix(text, "/") || strings.ContainsAny(text, " \t") {
		return nil
	}
	var out []command
	for _, c := range m.commands {
		if strings.HasPrefix(c.name, strings.ToLower(text[1:])) {
			out = append(out, c)
		}
	}
	return out
}

func (m model) updateIdle(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	sug := m.suggestions()
	switch msg.Type {
	case tea.KeyUp:
		if len(sug) > 0 {
			m.selected = (m.selected + len(sug) - 1) % len(sug)
		}
		return m, nil
	case tea.KeyDown:
		if len(sug) > 0 {
			m.selected = (m.selected + 1) % len(sug)
		}
		return m, nil
	case tea.KeyTab:
		if len(sug) > 0 {
			m.input.SetValue("/" + sug[min(m.selected, len(sug)-1)].name + " ")
			m.input.CursorEnd()
		}
		return m, nil
	case tea.KeyEsc:
		m.input.SetValue("")
		m.selected = 0
		return m, nil
	case tea.KeyEnter:
		text := strings.TrimSpace(m.input.Value())
		if len(sug) > 0 {
			text = "/" + sug[min(m.selected, len(sug)-1)].name
		}
		m.input.SetValue("")
		m.selected = 0
		if text == "" {
			return m, nil
		}
		return m.execute(text)
	}
	before := m.input.Value()
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	if m.input.Value() != before {
		m.selected = 0
	}
	return m, cmd
}

func (m model) execute(text string) (tea.Model, tea.Cmd) {
	echo := tea.Println(sAccent.Render("> ") + text)
	fields := strings.Fields(text)
	name := strings.ToLower(strings.TrimPrefix(fields[0], "/"))
	if !strings.HasPrefix(fields[0], "/") {
		return m, tea.Sequence(echo, tea.Println(sDim.Render("  Os comandos começam com /. Digite /ajuda para ver a lista.\n")))
	}
	for _, c := range m.commands {
		if c.name != name {
			continue
		}
		switch {
		case c.macro != nil:
			m.active = c.macro
			m.items = parseItems(nil, strings.Join(fields[1:], " "))
			if len(m.items) > 0 {
				return m.start(echo)
			}
			m.mode = modeCollecting
			m.input.Prompt = "+ "
			return m, echo
		case name == "ajuda":
			return m, tea.Sequence(echo, tea.Println(m.help()))
		case name == "limpar":
			return m, tea.Sequence(tea.ClearScreen, m.banner())
		case name == "sair":
			return m, tea.Sequence(echo, tea.Quit)
		}
	}
	return m, tea.Sequence(echo, tea.Println(sFail.Render("  Comando desconhecido: "+fields[0])+sDim.Render(" · /ajuda mostra a lista\n")))
}

func (m model) help() string {
	var b strings.Builder
	for _, c := range m.commands {
		fmt.Fprintf(&b, "  %s  %s\n", sAccent.Render(fmt.Sprintf("/%-8s", c.name)), c.desc)
	}
	b.WriteString(sDim.Render("\n  Dica: a lista pode ir junto do comando, ex.: /pdfs 12345 67890\n"))
	return b.String()
}

// ---- modo lista ----

// parseItems separa o texto por espaço, vírgula, ponto e vírgula ou quebra de
// linha e acrescenta em items, sem repetir.
func parseItems(items []string, text string) []string {
	seen := make(map[string]bool, len(items))
	for _, it := range items {
		seen[it] = true
	}
	for _, f := range strings.FieldsFunc(text, func(r rune) bool {
		return r == ',' || r == ';' || r == ' ' || r == '\t' || r == '\n' || r == '\r'
	}) {
		if !seen[f] {
			seen[f] = true
			items = append(items, f)
		}
	}
	return items
}

func (m model) updateCollecting(msg tea.KeyMsg, previous time.Time) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEsc:
		m.reset()
		return m, tea.Println(sDim.Render("  Cancelado.\n"))
	case tea.KeyEnter:
		text := strings.TrimSpace(m.input.Value())
		m.input.SetValue("")
		if text != "" {
			m.items = parseItems(m.items, text)
			return m, nil
		}
		// Linha em branco no meio de uma colagem não deve disparar a macro.
		if len(m.items) == 0 || time.Since(previous) < 150*time.Millisecond {
			return m, nil
		}
		return m.start(nil)
	}
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

func (m *model) reset() {
	m.mode = modeIdle
	m.active, m.items, m.cancel, m.events = nil, nil, nil, nil
	m.okCount, m.failures, m.current = 0, nil, macro.Event{}
	m.input.Prompt = "> "
	m.input.SetValue("")
}

// ---- execução ----

func (m model) start(before tea.Cmd) (tea.Model, tea.Cmd) {
	ctx, cancel := context.WithCancel(context.Background())
	m.mode = modeRunning
	m.cancel = cancel
	m.events = make(chan tea.Msg, 64)
	m.current = macro.Event{Total: len(m.items)}
	m.input.SetValue("")

	events, run, items := m.events, m.active.Run, m.items
	go func() {
		err := run(ctx, items, func(e macro.Event) { events <- runEventMsg(e) })
		events <- runDoneMsg{err}
	}()

	header := tea.Println(fmt.Sprintf("  %s %s", sBold.Render(m.active.Title),
		sDim.Render(fmt.Sprintf("· %d %s", len(items), m.active.ItemLabel))))
	return m, tea.Batch(tea.Sequence(before, header), m.spin.Tick, waitEvent(events))
}

func waitEvent(ch chan tea.Msg) tea.Cmd {
	return func() tea.Msg { return <-ch }
}

func (m model) onEvent(e macro.Event) (tea.Model, tea.Cmd) {
	var line tea.Cmd
	switch e.Kind {
	case macro.Progress:
		m.current = e
	case macro.OK:
		m.okCount++
		line = tea.Println(fmt.Sprintf("  %s %s  %s", sOK.Render("√"), e.Item, sDim.Render(e.Text)))
	case macro.Fail:
		m.failures = append(m.failures, e)
		line = tea.Println(fmt.Sprintf("  %s %s  %s", sFail.Render("×"), e.Item, sFail.Render(e.Text)))
	default:
		line = tea.Println("  " + sDim.Render(e.Text))
	}
	return m, tea.Batch(line, waitEvent(m.events))
}

func (m model) onDone(err error) (tea.Model, tea.Cmd) {
	var summary string
	switch {
	case errors.Is(err, context.Canceled):
		summary = sDim.Render(fmt.Sprintf("  Cancelado · %d abertos de %d", m.okCount, len(m.items)))
	case err != nil:
		summary = sFail.Render("  × " + err.Error())
	case len(m.failures) == 0:
		summary = sOK.Render(fmt.Sprintf("  Concluído · %d de %d abertos", m.okCount, len(m.items)))
	default:
		failed := make([]string, len(m.failures))
		for i, f := range m.failures {
			failed[i] = f.Item
		}
		summary = fmt.Sprintf("  Concluído · %s · %s\n  %s",
			sOK.Render(fmt.Sprintf("%d abertos", m.okCount)),
			sFail.Render(fmt.Sprintf("%d com falha", len(m.failures))),
			sDim.Render("Falharam: "+strings.Join(failed, ", ")))
	}
	m.reset()
	return m, tea.Println(summary + "\n")
}

// ---- tela ----

func (m model) View() string {
	box := sBox.Width(max(20, m.width-2))
	switch m.mode {
	case modeRunning:
		status := fmt.Sprintf("  %s Conectando ao SAP...", m.spin.View())
		if m.current.Index > 0 {
			status = fmt.Sprintf("  %s Processando %d/%d · %s", m.spin.View(), m.current.Index, m.current.Total, m.current.Item)
		}
		return status + sDim.Render("   Esc para cancelar") + "\n"

	case modeCollecting:
		head := fmt.Sprintf("  %s %s", sBold.Render(m.active.Title),
			sDim.Render(fmt.Sprintf("· %d %s na lista", len(m.items), m.active.ItemLabel)))
		hint := "  Cole ou digite os " + m.active.ItemLabel + " e tecle Enter · Esc cancela"
		if len(m.items) > 0 {
			hint = "  Enter com a linha vazia executa · Esc cancela"
		}
		return head + "\n" + box.BorderForeground(accent).Render(m.input.View()) + "\n" + sDim.Render(hint) + "\n"
	}

	out := box.BorderForeground(cDim).Render(m.input.View()) + "\n"
	sug := m.suggestions()
	if len(sug) == 0 {
		return out + sDim.Render("  / para comandos · Ctrl+C para sair") + "\n"
	}
	for i, c := range sug {
		name := fmt.Sprintf("/%-8s", c.name)
		if i == min(m.selected, len(sug)-1) {
			out += "  " + sAccent.Bold(true).Render(name) + "  " + c.desc + "\n"
		} else {
			out += "  " + sDim.Render(name+"  "+c.desc) + "\n"
		}
	}
	return out
}
