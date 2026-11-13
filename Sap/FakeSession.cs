using System;
using System.Threading;

namespace MacroApp.Sap
{
    /// <summary>Sessão de mentira usada com --simular. Materiais contendo "erro" falham.</summary>
    internal sealed class FakeSession : ISapSession
    {
        private string _material = "";

        public void SetText(string id, string text)
        {
            if (id.EndsWith("MATNR")) _material = text;
        }

        public void SendVKey(string window, int key) { Thread.Sleep(150); }
        public void Press(string id) { }
        public void PressButton(string id, string button) { Thread.Sleep(300); }
        public void Maximize(string window) { }

        public void StatusBar(out string type, out string text)
        {
            var failed = _material.IndexOf("erro", StringComparison.OrdinalIgnoreCase) >= 0;
            type = failed ? "E" : "";
            text = failed ? "Material " + _material + " não existe (simulado)" : "";
        }
    }
}
