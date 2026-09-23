# Go demo for github.com/ichbinblau/goamdsmi. See README.md; run `make run` on a ROCm host.

export CGO_ENABLED := 1
ROCM ?= /opt/rocm
# Where `make shim` puts libgoamdsmi_shim64.so and its headers.
SHIM ?= $(CURDIR)/.shim
GOAMDSMI := github.com/ichbinblau/goamdsmi

# cgo needs the shim header at build time and the .so at run time (rpath lets
# ./bin/amdsmi-demo run without LD_LIBRARY_PATH).
export CGO_CFLAGS  += -I$(SHIM)/include -I$(ROCM)/include
export CGO_LDFLAGS += -L$(SHIM)/lib -L$(ROCM)/lib -L$(ROCM)/lib64 -Wl,-rpath,$(SHIM)/lib
export LD_LIBRARY_PATH := $(SHIM)/lib:$(LD_LIBRARY_PATH):$(ROCM)/lib:$(ROCM)/lib64

.PHONY: shim build run check clean

# Build the cgo shim from the goamdsmi module source pinned in go.mod, so the
# C shim always matches the Go binding. Rebuilt when go.mod changes.
shim: $(SHIM)/lib/libgoamdsmi_shim64.so

$(SHIM)/lib/libgoamdsmi_shim64.so: go.mod
	go mod download $(GOAMDSMI)
	src=$$(go list -m -f '{{.Dir}}' $(GOAMDSMI))/goamdsmi_shim/smiwrapper && \
	mkdir -p $(SHIM)/include $(SHIM)/lib && \
	gcc -shared -fPIC -O2 -DENABLE_DEBUG_LEVEL=0 -o $@ $$src/amdsmi_go_shim.c \
	    -I$$src -I$(ROCM)/include -L$(ROCM)/lib -lamd_smi -Wl,-rpath,$(ROCM)/lib && \
	install -m 644 $$src/amdsmi_go_shim.h $$src/goamdsmi.h $(SHIM)/include/

check:
	@test -f $(ROCM)/include/amd_smi/amdsmi.h || { echo "MISSING: $(ROCM)/include/amd_smi/amdsmi.h (ROCm amd-smi headers)"; exit 1; }
	@ls $(ROCM)/lib*/libamd_smi.so >/dev/null 2>&1 || { echo "MISSING: libamd_smi.so under $(ROCM)/lib*"; exit 1; }
	@test -f $(SHIM)/lib/libgoamdsmi_shim64.so || { echo "MISSING: shim, run 'make shim'"; exit 1; }
	@echo "ROCm amd-smi + shim present"

build: shim
	go build -o bin/amdsmi-demo .

run: build
	./bin/amdsmi-demo

clean:
	rm -rf bin $(SHIM)
