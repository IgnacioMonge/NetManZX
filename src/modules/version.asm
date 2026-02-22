    ; Generate VERSION_STRING from define V
    ; V = Mmp...  (M=major digit, m=minor digit, p=patch digits optional)
    ; Examples: V=12  -> "1.2"
    ;           V=121 -> "1.2.1"
    ;           V=1210 -> "1.2.10"
    LUA ALLPASS
    v = tostring(sj.get_define("V"))
    maj = string.sub(v, 1, 1)
    min = string.sub(v, 2, 2)
    patch = string.sub(v, 3)

    ver = maj .. "." .. min
    if patch ~= nil and patch ~= "" then
        ver = ver .. "." .. patch
    end

    sj.insert_define("VERSION_STRING", "\"" .. ver .. "\"")
    ENDLUA