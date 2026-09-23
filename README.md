# amdsmi-demo-A

用 Go 调用 AMD SMI 读取 GPU 状态（时钟、利用率、功耗）的最小示例，依赖
[`github.com/ichbinblau/goamdsmi`](https://github.com/ichbinblau/goamdsmi)。

## 为什么用 `ichbinblau/goamdsmi`

官方 Go binding 位于 ROCm 单体仓库的 `rocm-systems/projects/amdsmi`，该目录没有
`go.mod`，直接 `go get` 会因整个仓库超过 500 MB 而失败：

```
$ go get github.com/ROCm/rocm-systems/projects/amdsmi@develop
go: ... create zip: module source tree too large (max size is 524288000 bytes)
```

`ichbinblau/goamdsmi` 从 develop（commit `820ea79`）中只抽取了 Go binding 和 C shim
源码，作为独立模块发布，包名仍为 `goamdsmi`。相对上游做了两处修复：一处 cgo 编译错误，
以及让 shim 同时兼容 amd-smi 26.x（ROCm 7.1 / 7.2）和 27.x。详见该仓库 README。

## 前置条件

- 装有 amdgpu 驱动和 ROCm（含 amd-smi 头文件和 `libamd_smi.so`）的主机。
  已在 MI355X + ROCm 7.1.1 上验证
- 以下二选一：
  - 宿主机上装有 Go ≥ 1.21、gcc 和 make
  - Docker（宿主机不需要装 Go）

cgo 链接的是 `libgoamdsmi_shim64.so`（shim），该库再调用 `libamd_smi.so`。标准 ROCm
安装**不带** shim。`make run` 会自动用 `go.mod` 中锁定版本的 goamdsmi 源码编译 shim，
输出到 `.shim/`，不需要手动编译。

## 快速开始

### 方式 A：在宿主机上运行

```bash
git clone https://github.com/ichbinblau/amdsmi-demo-A.git
cd amdsmi-demo-A
make run
```

### 方式 B：在 Docker 里运行

```bash
git clone https://github.com/ichbinblau/amdsmi-demo-A.git
cd amdsmi-demo-A

docker run -d --name go122 \
  --user $(id -u):$(id -g) -e HOME=/tmp \
  --device=/dev/kfd --device=/dev/dri \
  --group-add video --group-add $(getent group render | cut -d: -f3) \
  -v /opt/rocm:/opt/rocm:ro \
  -v $PWD:/work -w /work \
  golang:1.22 sleep infinity

docker exec go122 make run
```

- `--user $(id -u):$(id -g)` 让容器以宿主机用户身份运行。这样生成的 `bin/`、`.shim/`
  归你所有；git 也不会因为仓库属主不同而拒绝读取（否则 `go build` 会报
  `error obtaining VCS status`）。`HOME=/tmp` 为 Go 的构建缓存提供一个可写目录。
- 可选：golang 镜像里没有 libdrm，运行时会打印 `Fail to open libdrm_amdgpu.so.1`
  警告，但不影响结果。如需消除警告，以 root 身份安装：

  ```bash
  docker exec -u 0 go122 bash -c 'apt-get update -qq && apt-get install -y -qq libdrm-amdgpu1'
  ```

### 预期输出

```
AMD SMI reports 8 GPU(s)

GPU 0
  sclk       : 2308 MHz
  mclk       : 2000 MHz
  utilization: 100 %
  power      : 666.0 W (cap 1400.0 W)
...
```

demo 只通过 amd-smi 读取遥测数据，不会在 GPU 上跑计算，也不占用显存。

## Makefile 目标

| 目标 | 作用 |
|---|---|
| `make run` | 编译 shim（如需要）和 demo，然后运行 |
| `make shim` | 只编译 shim，输出到 `.shim/{include,lib}`。`go.mod` 改动后会重新编译 |
| `make check` | 检查 ROCm amd-smi 和 shim 是否存在 |
| `make clean` | 删除 `bin/` 和 `.shim/` |

可覆盖的变量：`ROCM`（默认 `/opt/rocm`）、`SHIM`（默认 `./.shim`）。

## 在自己的项目里使用 goamdsmi

1. 添加依赖：

   ```bash
   go get github.com/ichbinblau/goamdsmi@latest
   ```

2. 编译 shim：最简单的做法是把本仓库 `Makefile` 里的 `shim` 目标和 `CGO_*` /
   `LD_LIBRARY_PATH` 几行复制过去。也可以手动编译（在你的模块目录下执行）：

   ```bash
   SRC=$(go list -m -f '{{.Dir}}' github.com/ichbinblau/goamdsmi)/goamdsmi_shim/smiwrapper
   SHIM=$HOME/goamdsmi-shim
   mkdir -p $SHIM/include $SHIM/lib
   gcc -shared -fPIC -O2 -DENABLE_DEBUG_LEVEL=0 \
       -o $SHIM/lib/libgoamdsmi_shim64.so $SRC/amdsmi_go_shim.c \
       -I$SRC -I/opt/rocm/include -L/opt/rocm/lib -lamd_smi -Wl,-rpath,/opt/rocm/lib
   cp $SRC/amdsmi_go_shim.h $SRC/goamdsmi.h $SHIM/include/

   export CGO_ENABLED=1
   export CGO_CFLAGS="-I$SHIM/include"
   export CGO_LDFLAGS="-L$SHIM/lib"
   export LD_LIBRARY_PATH="$SHIM/lib:$LD_LIBRARY_PATH"
   ```

3. 调用示例：

   ```go
   import "github.com/ichbinblau/goamdsmi"

   if !goamdsmi.GO_gpu_init() {
       // 驱动未加载或找不到 libamd_smi.so
   }
   defer goamdsmi.GO_gpu_shutdown()

   n := int(goamdsmi.GO_gpu_num_monitor_devices())
   for i := 0; i < n; i++ {
       sclk  := uint64(goamdsmi.GO_gpu_dev_gpu_clk_freq_get_sclk(i)) // Hz
       busy  := uint32(goamdsmi.GO_gpu_dev_gpu_busy_percent_get(i))  // %
       power := uint64(goamdsmi.GO_gpu_dev_power_get(i))             // 微瓦
       _, _, _ = sclk, busy, power
   }
   ```

   getter 的返回值是 C 数值类型，需要在调用处转换成 Go 类型（如上所示）。

   在 amd-smi 26.x（ROCm 7.1 / 7.2）上，UMA carveout 和 TTM 相关函数
   （`GO_gpu_uma_carveout_*`、`GO_ttm_*`）会直接返回 `-1`，因为这个版本的 amd-smi
   没有对应 API。

## 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| `fatal error: amdsmi_go_shim.h: No such file or directory` | 还没编译 shim，或 `CGO_CFLAGS` 没指向 shim 头文件。在本仓库里执行 `make run` 会自动编译 |
| `cannot find -lgoamdsmi_shim64` | `CGO_LDFLAGS` 没指向 shim 所在目录 |
| 运行时报 `libgoamdsmi_shim64.so: cannot open shared object file` | `LD_LIBRARY_PATH` 里没有 shim 所在目录 |
| `fatal error: amd_smi/amdsmi.h: No such file or directory` | ROCm 不在 `/opt/rocm`（可用 `make ROCM=/path/to/rocm run` 指定），或 Docker 没挂载 `/opt/rocm` |
| `GO_gpu_init failed` | amdgpu 驱动未加载；或容器没有挂载 `/dev/kfd`、`/dev/dri`，没有加入 video/render 组 |
| `error obtaining VCS status: exit status 128` | 容器以 root 身份读取宿主机用户的 git 仓库被拒。按上面的命令加 `--user $(id -u):$(id -g)` |
| `go: command not found`（`docker exec ... bash -lc`） | login shell 会重置 `PATH`，改用 `bash -c` 或直接 `docker exec go122 make run` |
| `goamdsmi.go:740 ... *[16][256]_Ctype_char` | 用的是 goamdsmi v0.1.0 或上游 develop，请升级到 v0.1.1 及以上 |
| shim 编译报 `processor_type_t` / `amdsmi_uma_carveout_info_t` 等错误 | 用的是 goamdsmi v0.1.1 及以下，shim 不兼容 amd-smi 26.x，请升级到 v0.1.2 及以上 |
