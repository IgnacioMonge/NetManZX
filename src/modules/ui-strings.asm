    module start
; Keep descriptive startup text without consuming the remaining code space.
msg_preparing db "UART init...", 13, 0
msg_esp_config db "Configuring ESP...", 13, 0
    IFDEF NEXT
msg_probe_esp db "Probing ESP...", 0
msg_hw_reset db "Resetting ESP...", 0
    ENDIF
    endmodule

    module UI

; UI text shares the loaded data bank with the expanded font.
msg_connected_title db "Connected!", 0
msg_done_body       db "Now you can use network apps!", 0
    IFDEF HAS_ESXDOS
msg_save_presskey db "(S)ave to file or any key to exit...", 0
msg_save_ok     db "Config file saved!", 0
msg_save_fail   db "SD write error", 0
    ENDIF
; Old multi-line fail messages removed - replaced by showConnFailScreen
msg_press_key   db "Press any key to continue...", 0
msg_conn_attempt db "Connecting to...", 0
    IFDEF HAS_ESXDOS
msg_reco_attempt db "Reconnecting to...", 0
    ENDIF
msg_attempt_suffix db " (x/3)", 0
msg_break_cancel db "Press BREAK to cancel", 0
msg_open_net    db "Open network (no password needed)", 0
at_start        db 'AT+CWJAP="',0
at_start_old    db 'AT+CWJAP_DEF="',0
at_middle       db '","', 0
msg_ssid        db "Selected SSID:", 0
msg_pass        db "Password (BREAK=cancel, UP=show):", 0
msg_yes_anykey  db "(Y)es / any key = cancel", 0
at_quote_crlf   db '"', 0

msg_head
    db "NetManZX "
    db VERSION_STRING
    db " - Network manager", 0

msg_wifi_label
    db "WiFi:", 0

msg_help   db "Q/A:Nav O/P:Page R:Refresh D:Diagnostics", 0
msg_help_conn db "R:Refresh X:Disconnect D:Diagnostics", 0
    IFDEF HAS_ESXDOS
msg_help2  db "H:Hidden W:WPS L:Log C:Reconnect I:About", 0
    ELSE
msg_help2  db "H:Hidden W:WPS L:Log I:About", 0
    ENDIF

    module showDiagnostics
msg_diag_title db "DIAGNOSTICS", 0
msg_diag_opt1  db "Ping test", 0
msg_diag_opt2  db "Module info (firmware)", 0
msg_diag_opt3  db "Network info", 0
msg_diag_opt4  db "UART baud rate", 0
msg_diag_opt5  db "Static IP config", 0
msg_diag_opt6  db "Set hostname", 0
msg_diag_opt7  db "Config summary", 0
diagPtrs:
    dw msg_diag_opt1, msg_diag_opt2, msg_diag_opt3, msg_diag_opt4
    dw msg_diag_opt5, msg_diag_opt6, msg_diag_opt7
msg_diag_exit  db "ENTER:Select BREAK:Exit", 0

    endmodule

msg_baud_title db "UART BAUD RATE", 0
msg_no_at      db "No AT response (still in data mode?)", 0
cmd_uart_cur   db "AT+UART_CUR?", 0
cmd_uart_def   db "AT+UART_DEF?", 0
cmd_uart_plain db "AT+UART?", 0
lbl_baud_cur   db "Current: ", 0
lbl_baud_def   db "Default: ", 0
lbl_baud_plain db "UART: ", 0
msg_uart_none db "No UART info (no response).", 0
msg_uart_error db "UART query returned ERROR.", 0

    endmodule

    module Wifi
; Shared AT command strings (Z-terminated; sender appends CRLF)
S_AT            db "AT", 0
S_ATE0          db "ATE0", 0
S_AT_RST        db "AT+RST", 0
S_AT_SYSSTORE   db "AT+SYSSTORE=1", 0
S_AT_CWMODE     db "AT+CWMODE=1", 0
S_AT_CWMODE_DEF db "AT+CWMODE_DEF=1", 0
S_AT_CWAUTOCONN db "AT+CWAUTOCONN=1", 0
S_AT_CWJAP_Q    db "AT+CWJAP?", 0
S_AT_CWJAP_CUR  db "AT+CWJAP_CUR?", 0
S_AT_CWJAP_DEF  db "AT+CWJAP_DEF?", 0
S_AT_CWLAP      db "AT+CWLAP", 0
S_AT_CWLAP_EXT  db "AT+CWLAP=,,,,200,200", 0
S_AT_CWLAPOPT   db "AT+CWLAPOPT=0,31", 0
S_AT_CIFSR      db "AT+CIFSR", 0
S_AT_CIPMODE_NORMAL db "AT+CIPMODE=0", 0

    endmodule

    module UI
    module doPing
msg_ping_title  db "PING TEST", 0
msg_ip_prompt   db "Enter IP address:", 0
msg_ping_help   db "ENTER=ping, BREAK=cancel", 0
msg_pinging     db "Pinging ", 0
msg_dots        db "...", 0
cmd_ping_start  db "AT+PING=", '"', 0
msg_time_lbl    db "Response time: ", 0
msg_time_ms     db " ms", 0
msg_timeout     db "Request timed out", 0
    endmodule

    module doHostname
hn_title   db "SET HOSTNAME", 0
hn_prompt  db "Enter hostname:", 0
hn_set_to  db "Hostname set to:", 0
hn_err     db "Hostname failed!", 0
hn_cmd     db "AT+CWHOSTNAME=\"", 0
    endmodule
    endmodule
