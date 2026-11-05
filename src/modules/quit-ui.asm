; All targets confirm quitting, including builds without the clock overlay.
quitConfirm:
    call Keyboard.waitBreakRelease
    call debounce15
    ld a, 17
    ld c, ATTR_PRESS_KEY
    call Display.setAttr
    ld a, 17
    ld hl, .msg_quit
    call printAt0
    ld hl, msg_yes_anykey
    call Display.putStr
    call Keyboard.inKey
    and #DF
    cp 'Y'
    jp nz, renderListAndLoop
    call Keyboard.waitBreakRelease
    IFDEF NEXT
    di
    nextreg #02, #01
.hold
    jr .hold
    ELSE
    jp exitRestore
    ENDIF
.msg_quit db "Quit to BASIC? ", 0
