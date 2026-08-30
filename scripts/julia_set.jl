#!/usr/bin/env julia
# ============================================================
#  用 Julia 语言画 Julia 集 (Julia set)
#  迭代公式: z_{n+1} = z_n^2 + c
#
#  用法 (在仓库根目录):
#    julia -t auto --project=. scripts/julia_set.jl
#    julia -t auto --project=. scripts/julia_set.jl 1920 1080 -0.7269 0.1889 output/wallpaper.png
#    参数依次为: 宽 高 Re(c) Im(c) 输出路径
# ============================================================

using Images

# ---- 参数(命令行可覆盖)----
width   = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1024
height  = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 768
cre     = length(ARGS) >= 3 ? parse(Float64, ARGS[3]) : -0.8
cim     = length(ARGS) >= 4 ? parse(Float64, ARGS[4]) : 0.156
outpath = length(ARGS) >= 5 ? ARGS[5] : "output/julia_set.png"

max_iter = 500          # 最大迭代次数: 越大边界细节越丰富
escape_r = 4.0          # 逃逸半径
c = complex(cre, cim)

# ---- 视野(按长宽比缩放)----
span   = 2.8
aspect = width / height
xs = range(-span * aspect / 2, span * aspect / 2; length = width)
ys = range(-span / 2, span / 2; length = height)

# ---- IQ 余弦调色板: t ∈ [0,1] → RGB ----
function palette(t::Float64)
    a = [0.5, 0.5, 0.5]        # 基色
    b = [0.5, 0.5, 0.5]        # 振幅
    f = [1.0, 1.0, 1.0]        # 频率
    ph = [0.263, 0.416, 0.557] # 相位
    rgb = clamp.(a .+ b .* cospi.(2 .* (f .* t .+ ph)), 0.0, 1.0)
    return RGB{N0f8}(rgb[1], rgb[2], rgb[3])
end

# ---- 单像素逃逸时间, 返回平滑迭代数; -1 表示属于集合内部 ----
@inline function escape_time(z0::ComplexF64, c::ComplexF64, max_iter::Int, r2::Float64)
    z = z0
    n = 0
    while n < max_iter && abs2(z) <= r2
        z = z * z + c
        n += 1
    end
    n == max_iter && return -1.0
    return n + 1 - log2(log(abs(z)))   # 平滑处理, 消除色带
end

# ---- 主渲染: 按行多线程并行 ----
img = Matrix{RGB{N0f8}}(undef, height, width)
r2  = escape_r^2
Threads.@threads for j in 1:height
    y = ys[j]
    for i in 1:width
        nu = escape_time(complex(xs[i], y), c, max_iter, r2)
        if nu < 0
            img[j, i] = RGB{N0f8}(0, 0, 0)
        else
            t = (nu / max_iter)^0.4    # 幂次拉伸, 让颜色层次更丰富
            img[j, i] = palette(t)
        end
    end
end

d = dirname(outpath)
isempty(d) || mkpath(d)
save(outpath, img)
println("已保存: $outpath  (c = $cre + $(cim)im, $(width)×$(height), $(Threads.nthreads()) 线程)")
