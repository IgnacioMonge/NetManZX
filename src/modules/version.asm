    ; Generate VERSION_STRING from define V (and optional VSUB)
    ; V = Mmp...  (M=major digit, m=minor digit, p=patch digits optional)
    ; Examples: V=12  -> "1.2"
    ;           V=121 -> "1.2.1"
    ;           V=1210 -> "1.2.10"
    ; Optional: VSUB for sub-patch (V=143, VSUB=1 -> "1.4.3.1")
    LUA ALLPASS
    v = tostring(sj.get_define("V"))
    maj = string.sub(v, 1, 1)
    min = string.sub(v, 2, 2)
    patch = string.sub(v, 3)

    ver = maj .. "." .. min
    if patch ~= nil and patch ~= "" then
        ver = ver .. "." .. patch
    end

    -- Optional sub-patch level
    local ok, sub = pcall(sj.get_define, "VSUB")
    if ok and sub ~= nil then
        ver = ver .. "." .. tostring(sub)
    end

    sj.insert_define("VERSION_STRING", "\"" .. ver .. "\"")

    -- Build date: dd/mm/yyyy
    sj.insert_define("BUILD_DATE", "\"" .. os.date("%d/%m/%Y") .. "\"")
    ENDLUA