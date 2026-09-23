# Scheme A demo. Run `make setup` once, then `make run` on a ROCm host.

export CGO_ENABLED := 1
ROCM ?= /opt/rocm

# cgo needs to find the shim header at build time and the .so at run time.
export CGO_CFLAGS  += -I$(ROCM)/include
export CGO_LDFLAGS += -L$(ROCM)/lib -L$(ROCM)/lib64
export LD_LIBRARY_PATH := $(LD_LIBRARY_PATH):$(ROCM)/lib:$(ROCM)/lib64

.PHONY: setup build run check clean

setup:
	./setup.sh

check:
	@test -f $(ROCM)/include/amdsmi_go_shim.h || { echo "MISSING: $(ROCM)/include/amdsmi_go_shim.h"; exit 1; }
	@ls $(ROCM)/lib*/libgoamdsmi_shim64.so >/dev/null 2>&1 || { echo "MISSING: libgoamdsmi_shim64.so under $(ROCM)/lib*"; exit 1; }
	@echo "shim header + lib present"

build:
	go build -o bin/amdsmi-demo .

run: build
	./bin/amdsmi-demo

clean:
	rm -rf bin
