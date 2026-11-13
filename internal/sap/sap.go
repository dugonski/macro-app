// Package sap controla uma sessão aberta do SAP GUI via SAP GUI Scripting.
package sap

import (
	"errors"
	"strings"
	"time"
)

// Session é o conjunto de operações do SAP GUI Scripting usado pelas macros.
type Session interface {
	SetText(id, text string) error
	SendVKey(window string, key int) error
	Press(id string) error
	PressButton(id, button string) error
	Maximize(window string) error
	// StatusBar devolve o tipo (S, W, E, A, I) e o texto da barra de status.
	StatusBar() (msgType, text string, err error)
}

// ErrNotRunning indica que não há SAP GUI aberto e logado.
var ErrNotRunning = errors.New("SAP não encontrado: abra o SAP e faça login antes de executar")

// Simulate troca o SAP real por uma sessão falsa (para testar o app sem SAP).
var Simulate bool

// Run conecta na sessão ativa do SAP e executa fn com ela. Toda a chamada
// acontece em uma única thread do sistema, como o COM exige.
func Run(fn func(Session) error) error {
	if Simulate {
		return fn(&fakeSession{})
	}
	return run(fn)
}

type fakeSession struct{ material string }

func (f *fakeSession) SetText(id, text string) error {
	if strings.HasSuffix(id, "MATNR") {
		f.material = text
	}
	return nil
}
func (f *fakeSession) SendVKey(string, int) error { time.Sleep(150 * time.Millisecond); return nil }
func (f *fakeSession) Press(string) error         { return nil }
func (f *fakeSession) PressButton(string, string) error {
	time.Sleep(300 * time.Millisecond)
	return nil
}
func (f *fakeSession) Maximize(string) error { return nil }
func (f *fakeSession) StatusBar() (string, string, error) {
	if strings.Contains(strings.ToLower(f.material), "erro") {
		return "E", "Material " + f.material + " não existe (simulado)", nil
	}
	return "", "", nil
}
