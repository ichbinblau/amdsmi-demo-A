package main

import (
	"fmt"
	"os"

	"github.com/ichbinblau/goamdsmi"
)

func main() {
	// Must init before any other call; it loads libamd_smi internal state.
	if !goamdsmi.GO_gpu_init() {
		fmt.Fprintln(os.Stderr, "GO_gpu_init failed: is the amdgpu driver loaded and libamd_smi.so reachable?")
		os.Exit(1)
	}
	defer goamdsmi.GO_gpu_shutdown()

	n := int(goamdsmi.GO_gpu_num_monitor_devices())
	fmt.Printf("AMD SMI reports %d GPU(s)\n\n", n)

	// The getters return C numeric types; convert them to Go numerics at the
	// call site. Name getters return *C.char and are painful to use across
	// package boundaries, so this demo stays on the numeric ones.
	for i := 0; i < n; i++ {
		sclk := uint64(goamdsmi.GO_gpu_dev_gpu_clk_freq_get_sclk(i)) // Hz
		mclk := uint64(goamdsmi.GO_gpu_dev_gpu_clk_freq_get_mclk(i)) // Hz
		busy := uint32(goamdsmi.GO_gpu_dev_gpu_busy_percent_get(i))  // %
		power := uint64(goamdsmi.GO_gpu_dev_power_get(i))            // microwatts
		powCap := uint64(goamdsmi.GO_gpu_dev_power_cap_get(i))       // microwatts

		fmt.Printf("GPU %d\n", i)
		fmt.Printf("  sclk       : %.0f MHz\n", float64(sclk)/1e6)
		fmt.Printf("  mclk       : %.0f MHz\n", float64(mclk)/1e6)
		fmt.Printf("  utilization: %d %%\n", busy)
		fmt.Printf("  power      : %.1f W (cap %.1f W)\n\n",
			float64(power)/1e6, float64(powCap)/1e6)
	}
}
