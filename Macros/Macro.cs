using System;
using System.Collections.Generic;
using System.Threading;

namespace MacroApp.Macros
{
    public enum EventKind
    {
        Info,     // mensagem solta
        Progress, // começou a processar Item
        Ok,       // Item concluído
        Fail      // Item falhou; Text explica
    }

    public sealed class MacroEvent
    {
        public EventKind Kind;
        public string Item;
        public string Text;
        public int Index; // posição do item (base 1)
        public int Total;
    }

    /// <summary>Uma automação que recebe uma lista de itens (ex.: part numbers).</summary>
    public abstract class Macro
    {
        /// <summary>Nome usado no terminal, sem a barra.</summary>
        public abstract string Command { get; }
        public abstract string Title { get; }
        public abstract string Description { get; }
        /// <summary>Como chamar os itens da lista.</summary>
        public abstract string ItemLabel { get; }

        public abstract void Run(IList<string> items, Action<MacroEvent> emit, CancellationToken cancel);

        /// <summary>Macros disponíveis. Para criar uma nova, adicione aqui.</summary>
        public static readonly Macro[] All = { new PdfsMd04() };
    }
}
