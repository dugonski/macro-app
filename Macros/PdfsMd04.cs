using System;
using System.Collections.Generic;
using System.Threading;
using MacroApp.Sap;

namespace MacroApp.Macros
{
    /// <summary>Abre no navegador o PDF de cada part number pela MD04.</summary>
    public sealed class PdfsMd04 : Macro
    {
        private const string Centro = "8500";
        private const string Campos = "wnd[0]/usr/tabsTAB300/tabpF01/ssubINCLUDE300:SAPMM61R:0301/";

        public override string Command { get { return "pdfs"; } }
        public override string Title { get { return "PDFs MD04"; } }
        public override string Description { get { return "Abre no navegador o PDF de cada part number (MD04, centro " + Centro + ")"; } }
        public override string ItemLabel { get { return "part numbers"; } }

        public override void Run(IList<string> items, Action<MacroEvent> emit, CancellationToken cancel)
        {
            SapGui.Run(sap =>
            {
                try { sap.Maximize("wnd[0]"); } catch (SapException) { }

                for (var i = 0; i < items.Count; i++)
                {
                    cancel.ThrowIfCancellationRequested();
                    var material = items[i];
                    emit(new MacroEvent { Kind = EventKind.Progress, Item = material, Index = i + 1, Total = items.Count });
                    try
                    {
                        AbrirPdf(sap, material);
                        emit(new MacroEvent { Kind = EventKind.Ok, Item = material, Text = "PDF aberto" });
                    }
                    catch (SapException ex)
                    {
                        emit(new MacroEvent { Kind = EventKind.Fail, Item = material, Text = ex.Message });
                    }
                }
            });
        }

        private static void AbrirPdf(ISapSession sap, string material)
        {
            sap.SetText("wnd[0]/tbar[0]/okcd", "/nmd04");
            sap.SendVKey("wnd[0]", 0);

            sap.SetText(Campos + "ctxtRM61R-MATNR", material);
            sap.SetText(Campos + "ctxtRM61R-WERKS", Centro);
            sap.SendVKey("wnd[0]", 0);

            string tipo, texto;
            sap.StatusBar(out tipo, out texto);
            if (tipo == "E" || tipo == "A")
                throw new SapException(string.IsNullOrEmpty(texto) ? "o SAP recusou o material" : texto);

            sap.SendVKey("wnd[0]", 2);
            sap.PressButton("wnd[0]/titl/shellcont[1]/shell", "ZZZ_VIEW");

            // Volta para a tela inicial; a próxima iteração recomeça com /nmd04 de qualquer forma.
            for (var i = 0; i < 3; i++)
            {
                try { sap.Press("wnd[0]/tbar[0]/btn[3]"); } catch (SapException) { }
            }
        }
    }
}
