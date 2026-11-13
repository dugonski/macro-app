// Package macro define as macros que o app sabe executar.
package macro

import "context"

type EventKind int

const (
	Info     EventKind = iota // mensagem solta
	Progress                  // começou a processar Item
	OK                        // Item concluído
	Fail                      // Item falhou; Text explica
)

type Event struct {
	Kind  EventKind
	Item  string
	Text  string
	Index int // posição do item (base 1)
	Total int
}

// Macro é uma automação que recebe uma lista de itens (ex.: part numbers).
type Macro struct {
	Command     string // nome usado no terminal, sem a barra
	Title       string
	Description string
	ItemLabel   string // como chamar os itens da lista
	Run         func(ctx context.Context, items []string, emit func(Event)) error
}

// All lista as macros disponíveis. Para criar uma nova, adicione aqui.
func All() []Macro {
	return []Macro{pdfsMD04}
}
