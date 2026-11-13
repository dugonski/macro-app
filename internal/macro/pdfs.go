package macro

import (
	"context"
	"errors"

	"github.com/dugonski/macro-app/internal/sap"
)

const (
	centro     = "8500"
	md04Campos = "wnd[0]/usr/tabsTAB300/tabpF01/ssubINCLUDE300:SAPMM61R:0301/"
)

var pdfsMD04 = Macro{
	Command:     "pdfs",
	Title:       "PDFs MD04",
	Description: "Abre no navegador o PDF de cada part number (MD04, centro " + centro + ")",
	ItemLabel:   "part numbers",
	Run:         runPDFsMD04,
}

func runPDFsMD04(ctx context.Context, items []string, emit func(Event)) error {
	return sap.Run(func(s sap.Session) error {
		_ = s.Maximize("wnd[0]")
		for i, material := range items {
			if err := ctx.Err(); err != nil {
				return err
			}
			ev := Event{Item: material, Index: i + 1, Total: len(items)}
			ev.Kind = Progress
			emit(ev)
			if err := abrirPDF(s, material); err != nil {
				ev.Kind, ev.Text = Fail, err.Error()
			} else {
				ev.Kind, ev.Text = OK, "PDF aberto"
			}
			emit(ev)
		}
		return nil
	})
}

func abrirPDF(s sap.Session, material string) error {
	if err := s.SetText("wnd[0]/tbar[0]/okcd", "/nmd04"); err != nil {
		return err
	}
	if err := s.SendVKey("wnd[0]", 0); err != nil {
		return err
	}
	if err := s.SetText(md04Campos+"ctxtRM61R-MATNR", material); err != nil {
		return err
	}
	if err := s.SetText(md04Campos+"ctxtRM61R-WERKS", centro); err != nil {
		return err
	}
	if err := s.SendVKey("wnd[0]", 0); err != nil {
		return err
	}
	if tipo, texto, err := s.StatusBar(); err == nil && (tipo == "E" || tipo == "A") {
		if texto == "" {
			texto = "o SAP recusou o material"
		}
		return errors.New(texto)
	}
	if err := s.SendVKey("wnd[0]", 2); err != nil {
		return err
	}
	if err := s.PressButton("wnd[0]/titl/shellcont[1]/shell", "ZZZ_VIEW"); err != nil {
		return err
	}
	// Volta para a tela inicial; a próxima iteração recomeça com /nmd04 de qualquer forma.
	for range 3 {
		_ = s.Press("wnd[0]/tbar[0]/btn[3]")
	}
	return nil
}
