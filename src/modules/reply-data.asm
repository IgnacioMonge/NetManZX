; Reply tables share the static-data area with the AT command strings.
    module Wifi
S_AT_CIPSTA     db "AT+CIPSTA?", 0
S_AT_CIPSTA_CUR db "AT+CIPSTA_CUR?", 0
dbg_eol          db 13, 0
dbg_tx_cwjap     db "AT+CWJAP=<hidden>", 13, 10, 0
dbg_rx_ok       db "<< OK", 13, 10, 0
dbg_rx_error    db "<< ERROR", 13, 10, 0
    module getConnectionInfo
cifsrFields
    db "IFSR:STA", 0
    db 'I' : dw Wifi.ip_buffer : db 16, 'P,"', 0
    db 'M' : dw Wifi.ci_mac : db 17, 'AC,"', 0
    db 0
cipstaFields
    db "IPSTA", 0, ':'
    db 'g' : dw Wifi.ci_gateway : db 16, 'ateway:"', 0
    db 'n' : dw Wifi.ci_netmask : db 16, 'etmask:"', 0
    db 0
curSuffix db "CUR:", 0
    endmodule
    endmodule
    module UI
    module checkAsyncWifi
pat_ipd    db "+IPD,", 3
pat_discon db "WIFI DISCONNECT", 13, 10, UI.ASYNC_EVENT_DISCONNECT
pat_gotip  db "GOT IP", 13, 10, UI.ASYNC_EVENT_GOTIP
    endmodule
    endmodule
