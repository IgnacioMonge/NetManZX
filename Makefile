# ============================================================
# NetManZX Makefile (SpecTalkZX-style pipeline)
# Targets: uno (default), ay, next, all
# ============================================================

.DEFAULT_GOAL := uno

# ------------------------------------------------------------
# Toolchain / project
# ------------------------------------------------------------
ASM      = sjasmplus
SRCDIR   = src
BUILDDIR = build
LOGDIR   = log

MAIN       = $(SRCDIR)/main.asm
OUTPUT_TAP = netmanzx.tap

# ------------------------------------------------------------
# Assembler flags
# ------------------------------------------------------------
ASMFLAGS = --fullpath --nologo --msg=war

# ------------------------------------------------------------
# Platform (Windows-focused, works on Linux too)
# ------------------------------------------------------------
ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /C

define MKDIR_P
	@if not exist "$(1)" mkdir "$(1)"
endef

define CHECK_TOOL
	@where $(1) >NUL 2>NUL || (powershell -NoProfile -Command "Write-Host '[ERR] Missing tool: $(1)' -ForegroundColor Red" & exit /b 1)
endef

define CHECK_FILE
	@if not exist "$(1)" (powershell -NoProfile -Command "Write-Host '[ERR] Missing file: $(1)' -ForegroundColor Red" & exit /b 1)
endef

define BANNER
	@powershell -NoProfile -Command "Write-Host '============================================================' -ForegroundColor DarkGray"
endef

define TITLE
	@powershell -NoProfile -Command "Write-Host '$(1)' -ForegroundColor White"
endef

define STEP
	@powershell -NoProfile -Command "Write-Host ('[{0}] {1}' -f '$(1)','$(2)') -ForegroundColor Cyan"
endef

define OK
	@powershell -NoProfile -Command "Write-Host ('[OK] {0}' -f '$(1)') -ForegroundColor Green"
endef

define INFO
	@powershell -NoProfile -Command "Write-Host '$(1)' -ForegroundColor Gray"
endef

define RUN_ASM
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Force -Path '$(BUILDDIR)' | Out-Null; New-Item -ItemType Directory -Force -Path '$(LOGDIR)' | Out-Null; $$ts=(Get-Date).ToString('yyyyMMdd_HHmmss'); $$pretty=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); $$log='$(LOGDIR)/build_'+$$ts+'.log'; $$last='$(LOGDIR)/last_build.log'; @('============================================================','NetManZX - Build Log ($(1))','Date: '+$$pretty,'============================================================','ASMFLAGS=$(ASMFLAGS) $(2)','CMD=$(ASM) $(ASMFLAGS) $(2) -i$(SRCDIR) -iassets $(MAIN)','--------------------------------') | Set-Content -Encoding ASCII $$log; & '$(ASM)' $(ASMFLAGS) $(2) -i'$(SRCDIR)' -i'assets' '$(MAIN)' 2>&1 | Tee-Object -FilePath $$log -Append; Copy-Item -Force $$log $$last | Out-Null; Write-Output $$pretty | Set-Content -Encoding ASCII '$(LOGDIR)/last_build_date.txt'"
endef

define ECHO_SIZE
	@powershell -NoProfile -Command "if(Test-Path '$(1)'){ $$s=(Get-Item '$(1)').Length; Write-Host ('Binary TAP size: '+$$s+' bytes') -ForegroundColor Gray }"
endef

define MOVE_FILE
	@move /y "$(1)" "$(2)" >NUL 2>&1
endef

define CLEAN_CMD
	@if exist "$(OUTPUT_TAP)" del /q "$(OUTPUT_TAP)"
	@if exist "*.lst" del /q *.lst
	@if exist "*.sym" del /q *.sym
	@if exist "$(BUILDDIR)" rmdir /s /q "$(BUILDDIR)"
endef

define CLEAN_ALL
	@if exist "$(OUTPUT_TAP)" del /q "$(OUTPUT_TAP)"
	@if exist "*.lst" del /q *.lst
	@if exist "*.sym" del /q *.sym
	@if exist "$(BUILDDIR)" rmdir /s /q "$(BUILDDIR)"
	@if exist "$(LOGDIR)" rmdir /s /q "$(LOGDIR)"
endef

else
SHELL := /bin/sh

define MKDIR_P
	@mkdir -p "$(1)"
endef

define CHECK_TOOL
	@command -v "$(1)" >/dev/null 2>&1 || { echo "[ERR] Missing tool: $(1)"; exit 1; }
endef

define CHECK_FILE
	@test -f "$(1)" || { echo "[ERR] Missing file: $(1)"; exit 1; }
endef

define BANNER
	@printf "============================================================\n"
endef

define TITLE
	@printf "%s\n" "$(1)"
endef

define STEP
	@printf "[%s] %s\n" "$(1)" "$(2)"
endef

define OK
	@printf "[OK] %s\n" "$(1)"
endef

define INFO
	@printf "%s\n" "$(1)"
endef

define RUN_ASM
	@set -e; \
	mkdir -p "$(BUILDDIR)" "$(LOGDIR)"; \
	ts="$$(date +%Y%m%d_%H%M%S)"; \
	pretty="$$(date '+%Y-%m-%d %H:%M:%S')"; \
	log="$(LOGDIR)/build_$${ts}.log"; \
	last="$(LOGDIR)/last_build.log"; \
	echo "$$pretty" > "$(LOGDIR)/last_build_date.txt"; \
	{ \
	  echo "============================================================"; \
	  echo "NetManZX - Build Log ($(1))"; \
	  echo "Date: $${pretty}"; \
	  echo "============================================================"; \
	  echo "ASMFLAGS=$(ASMFLAGS) $(2)"; \
	  echo "--------------------------------"; \
	} > "$$log"; \
	$(ASM) $(ASMFLAGS) $(2) -i$(SRCDIR) -iassets $(MAIN) 2>&1 | tee -a "$$log"; \
	cp -f "$$log" "$$last"
endef

define ECHO_SIZE
	@{ [ -f "$(1)" ] && printf "Binary TAP size: %s bytes\n" "$$(wc -c < "$(1)")"; } 2>/dev/null || true
endef

define MOVE_FILE
	@mv -f "$(1)" "$(2)" 2>/dev/null || true
endef

define CLEAN_CMD
	@rm -f $(OUTPUT_TAP) *.lst *.sym 2>/dev/null || true
	@rm -rf $(BUILDDIR) 2>/dev/null || true
endef

define CLEAN_ALL
	@rm -f $(OUTPUT_TAP) *.lst *.sym 2>/dev/null || true
	@rm -rf $(BUILDDIR) $(LOGDIR) 2>/dev/null || true
endef

endif

# ------------------------------------------------------------
# Common steps
# ------------------------------------------------------------

dirs:
	$(call MKDIR_P,$(BUILDDIR))
	$(call MKDIR_P,$(LOGDIR))

preflight:
	$(call BANNER)
	$(call TITLE,NetManZX - Build Pipeline)
	$(call BANNER)
	$(call STEP,0/3,Checking toolchain and sources)
	$(call CHECK_TOOL,$(ASM))
	$(call CHECK_FILE,$(MAIN))
	$(call OK,Dependencies OK)

clean_step:
	$(call BANNER)
	$(call STEP,1/3,Cleaning)
	$(call CLEAN_CMD)
	$(call OK,Clean complete.)

info_step:
	$(call BANNER)
	$(call STEP,3/3,Info)
	$(call INFO,Output: $(BUILDDIR)/$(OUTPUT_TAP))
	$(call INFO,Build log: $(LOGDIR)/last_build.log)
	$(call ECHO_SIZE,$(BUILDDIR)/$(OUTPUT_TAP))
	$(call BANNER)

# ------------------------------------------------------------
# Build steps
# ------------------------------------------------------------

build_uno:
	$(call BANNER)
	$(call STEP,2/3,Build UNO)
	$(call INFO,Target: ZX-Uno / DivMMC)
	$(call INFO,Flags: -DUNO -DTAP)
	$(call RUN_ASM,UNO,-DUNO -DTAP)
	$(call MKDIR_P,$(BUILDDIR))
	$(call MOVE_FILE,$(OUTPUT_TAP),$(BUILDDIR)/$(OUTPUT_TAP))
	$(call OK,Build complete.)

build_ay:
	$(call BANNER)
	$(call STEP,2/3,Build AY)
	$(call INFO,Target: AY-UART / ZX-Badaloc)
	$(call INFO,Flags: -DAY -DTAP)
	$(call RUN_ASM,AY,-DAY -DTAP)
	$(call MKDIR_P,$(BUILDDIR))
	$(call MOVE_FILE,$(OUTPUT_TAP),$(BUILDDIR)/$(OUTPUT_TAP))
	$(call OK,Build complete.)

build_next:
	$(call BANNER)
	$(call STEP,2/3,Build NEXT)
	$(call INFO,Target: ZX Spectrum Next)
	$(call INFO,Flags: -DNEXT -DTAP)
	$(call RUN_ASM,NEXT,-DNEXT -DTAP)
	$(call MKDIR_P,$(BUILDDIR))
	$(call MOVE_FILE,$(OUTPUT_TAP),$(BUILDDIR)/$(OUTPUT_TAP))
	$(call OK,Build complete.)

# ------------------------------------------------------------
# Main targets
# ------------------------------------------------------------

uno: dirs preflight clean_step build_uno info_step

ay: dirs preflight clean_step build_ay info_step

next: dirs preflight clean_step build_next info_step

all: dirs preflight clean_step
	$(call BANNER)
	$(call STEP,2/3,Building all targets)
	$(call RUN_ASM,UNO,-DUNO -DTAP)
	$(call MOVE_FILE,$(OUTPUT_TAP),$(BUILDDIR)/netmanzx-uno.tap)
	$(call RUN_ASM,AY,-DAY -DTAP)
	$(call MOVE_FILE,$(OUTPUT_TAP),$(BUILDDIR)/netmanzx-ay.tap)
	$(call RUN_ASM,NEXT,-DNEXT -DTAP)
	$(call MOVE_FILE,$(OUTPUT_TAP),$(BUILDDIR)/netmanzx-next.tap)
	$(call OK,All builds complete.)
	$(call BANNER)
	$(call INFO,Output files in $(BUILDDIR)/)
	$(call BANNER)

clean:
	$(call CLEAN_ALL)
	$(call OK,Cleaned.)

info:
	$(call BANNER)
	$(call TITLE,NetManZX - Build Info)
	$(call BANNER)
	@echo ASMFLAGS : $(ASMFLAGS)
	@echo MAIN     : $(MAIN)
	@echo OUTPUT   : $(OUTPUT_TAP)
	@echo.
	@echo Targets:
	@echo   make uno   - ZX-Uno / DivMMC [default]
	@echo   make ay    - AY-UART / ZX-Badaloc
	@echo   make next  - ZX Spectrum Next
	@echo   make all   - Build all targets
	@echo   make clean - Remove build artifacts
	$(call BANNER)

.PHONY: uno ay next all clean info dirs preflight clean_step build_uno build_ay build_next info_step
