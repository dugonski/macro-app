using System;

namespace MacroApp.Sap
{
    /// <summary>Operações do SAP GUI Scripting usadas pelas macros.</summary>
    public interface ISapSession
    {
        void SetText(string id, string text);
        void SendVKey(string window, int key);
        void Press(string id);
        void PressButton(string id, string button);
        void Maximize(string window);

        /// <summary>Tipo (S, W, E, A, I) e texto da barra de status.</summary>
        void StatusBar(out string type, out string text);
    }

    public sealed class SapException : Exception
    {
        public SapException(string message) : base(message) { }
    }
}
