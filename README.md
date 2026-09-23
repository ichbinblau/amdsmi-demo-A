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
源码，作为独立模块发布，包名仍为 `goamdsmi`。v0.1.1 修复了上游一处 cgo 编译错误，
详见该仓库 README。

## 前置条件

- 装有 amdgpu 驱动和 ROCm 的主机（已在 MI355X + ROCm 7.1.1 上验证）
- Go ≥ 1.21，并开启 `CGO_ENABLED=1`
- gcc
- **cgo shim**：`amdsmi_go_shim.h` 和 `libgoamdsmi_shim64.so`

cgo 链接的是 `libgoamdsmi_shim64.so`，该库再调用 `libamd_smi.so`。标准 ROCm 安装
**不带**这个 shim，需要自己编译（见下一节）。

## 1. 编译 shim

shim 源码在 goamdsmi 仓库的 `goamdsmi_shim/smiwrapper/` 目录下：

```bash
git clone https://github.com/ichbinblau/goamdsmi.git
cd goamdsmi/goamdsmi_shim/smiwrapper

mkdir -p ~/goamdsmi-shim/{include,lib}
gcc -shared -fPIC -O2 -DENABLE_DEBUG_LEVEL=0 \
    -o ~/goamdsmi-shim/lib/libgoamdsmi_shim64.so amdsmi_go_shim.c \
    -I. -I/opt/rocm/include -L/opt/rocm/lib -lamd_smi -Wl,-rpath,/opt/rocm/lib
cp amdsmi_go_shim.h goamdsmi.h ~/goamdsmi-shim/include/
```

> **ROCm 版本注意**：shim 来自 develop 分支，用到了一些较新的 amd-smi API
> （UMA carveout、TTM 等）。如果本机 ROCm 较旧（例如 7.1.1），编译会报
> `implicit declaration` / `unknown type`：
>
> - `amdsmi_get_processor_handles_by_type`：7.1.1 的库里有这个符号，但头文件里的
>   声明被 `#ifdef ENABLE_ESMI_LIB` 挡住了。在 `amdsmi_go_shim.c` 中手动补一个函数
>   原型即可。
> - `goamdsmi_gpu_uma_carveout_*` 和 `goamdsmi_ttm_*`：7.1.1 中没有对应 API，把这几个
>   函数体改成直接 `return -1;`。
>
> 这样修改后的 shim 只适用于本机；只要不调用上述函数，其余接口都能正常工作。

## 2. 在自己的项目里使用 goamdsmi

```bash
go get github.com/ichbinblau/goamdsmi@v0.1.1
```

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

编译和运行时，要让 cgo 找到 shim：

```bash
export CGO_ENABLED=1
export CGO_CFLAGS="-I$HOME/goamdsmi-shim/include"
export CGO_LDFLAGS="-L$HOME/goamdsmi-shim/lib"
export LD_LIBRARY_PATH="$HOME/goamdsmi-shim/lib:$LD_LIBRARY_PATH"
```

如果把 shim 安装到 `/opt/rocm/include` 和 `/opt/rocm/lib`，就不需要设置
`CGO_CFLAGS` 和 `CGO_LDFLAGS`（goamdsmi 默认搜索这两个路径）。

## 3. 运行本 demo

### 方式 A：在宿主机上运行

```bash
# 设置好上一节的环境变量，然后：
make run
```

`make check` 只检查 `/opt/rocm` 下有没有 shim。如果 shim 放在别的目录，这项检查会
报 MISSING，可以忽略，`make run` 不依赖它。

### 方式 B：在 Docker 里运行（宿主机不需要装 Go）

```bash
docker run -d --name go122 \
  --device=/dev/kfd --device=/dev/dri \
  --group-add video --group-add $(getent group render | cut -d: -f3) \
  -v /opt/rocm:/opt/rocm:ro \
  -v $HOME/goamdsmi-shim:/opt/goamdsmi:ro \
  -v $PWD:/work -w /work \
  -e CGO_CFLAGS=-I/opt/goamdsmi/include \
  -e CGO_LDFLAGS=-L/opt/goamdsmi/lib \
  -e LD_LIBRARY_PATH=/opt/goamdsmi/lib \
  -e GOFLAGS=-buildvcs=false \
  golang:1.22 sleep infinity

# 可选：安装 libdrm，消除 "Fail to open libdrm_amdgpu.so.1" 警告
docker exec go122 bash -c 'apt-get update -qq && apt-get install -y -qq libdrm-amdgpu1'

docker exec go122 bash -c 'cd /work && make run'
```

注意：

- 执行 `docker exec` 时用 `bash -c`，不要用 `bash -lc`。login shell 会重置 `PATH`，
  导致找不到 `go`。
- 容器以 root 运行，而挂载进来的 git 仓库属于宿主机用户，git 会拒绝读取，`go build`
  报 `error obtaining VCS status`。`GOFLAGS=-buildvcs=false` 用来关闭 Go 的 VCS 信息
  嵌入，从而避开这个问题。

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

## 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| `fatal error: amdsmi_go_shim.h: No such file or directory` | 没有 shim，或 `CGO_CFLAGS` 没指向 shim 头文件 |
| `cannot find -lgoamdsmi_shim64` | `CGO_LDFLAGS` 没指向 shim 所在目录 |
| 运行时报 `libgoamdsmi_shim64.so: cannot open shared object file` | `LD_LIBRARY_PATH` 里没有 shim 所在目录 |
| `GO_gpu_init failed` | amdgpu 驱动未加载；或容器没有挂载 `/dev/kfd`、`/dev/dri`，没有加入 video/render 组 |
| `error obtaining VCS status: exit status 128` | 容器里的 root 读不了宿主机用户的 git 仓库；设置 `GOFLAGS=-buildvcs=false` |
| `goamdsmi.go:740 ... *[16][256]_Ctype_char` | 用的是 v0.1.0 或上游 develop，请升级到 v0.1.1 |
