# Abre no navegador o PDF de cada part number pela MD04.
@{
    Comando   = 'pdfs'
    Titulo    = 'PDFs MD04'
    Descricao = 'Abre no navegador o PDF de cada part number (MD04, centro 8500)'
    Rotulo    = 'part numbers'
    Sucesso   = 'PDF aberto'

    # Roda uma vez, antes do primeiro item.
    Inicio    = {
        Sap-Maximizar 'wnd[0]'
    }

    # Roda para cada item da lista. Se der erro, o item é marcado como falha
    # e o app segue para o próximo.
    PorItem   = {
        param($material)
        $centro = '8500'
        $campos = 'wnd[0]/usr/tabsTAB300/tabpF01/ssubINCLUDE300:SAPMM61R:0301/'

        Sap-Texto 'wnd[0]/tbar[0]/okcd' '/nmd04'
        Sap-Tecla 'wnd[0]' 0

        Sap-Texto ($campos + 'ctxtRM61R-MATNR') $material
        Sap-Texto ($campos + 'ctxtRM61R-WERKS') $centro
        Sap-Tecla 'wnd[0]' 0
        Sap-ConferirStatus

        Sap-Tecla 'wnd[0]' 2
        Sap-Botao 'wnd[0]/titl/shellcont[1]/shell' 'ZZZ_VIEW'

        # Volta para a tela inicial; o próximo item recomeça com /nmd04 de qualquer forma.
        foreach ($i in 1..3) { Sap-Clicar 'wnd[0]/tbar[0]/btn[3]' -IgnorarErro }
    }
}
