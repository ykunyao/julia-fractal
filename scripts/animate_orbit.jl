#!/usr/bin/env julia
# ============================================================
#  分形呼吸: 让参数 c 沿圆轨道绕一圈, 看 Julia 集形态连续流转
#  c(α) = R·e^{iα},  α ∈ [0, 2π)
#
#  用法 (在仓库根目录):
#    julia -t auto --project=. scripts/animate_orbit.jl
#  产物: output/fractal_orbit.gif
# ============================================================

using Images
using Printf

const ROOT      = dirname(@__DIR__)          # 仓库根目录
const W, H      = 480, 360
const NFRAMES   = 150
const ORBIT_R   = 0.7885                     # 经典轨道半径, 形态变化最丰富
const MAX_ITER  = 200
const ESCAPE_R2 = 16.0
const FPS       = 20
const OUTDIR    = joinpath(ROOT, "output", "frames")
const GIF_PATH  = joinpath(ROOT, "output", "fractal_orbit.gif")

half_y = 1.35
half_x = half_y * W / H
xs = range(-half_x, half_x; length = W)
ys = range(-half_y, half_y; length = H)

# ---- IQ 余弦调色板(与静态渲染保持一致)----
function palette(t::Float64)
    a = [0.5, 0.5, 0.5]
    b = [0.5, 0.5, 0.5]
    f = [1.0, 1.0, 1.0]
    ph = [0.263, 0.416, 0.557]
    rgb = clamp.(a .+ b .* cospi.(2 .* (f .* t .+ ph)), 0.0, 1.0)
    return RGB{N0f8}(rgb[1], rgb[2], rgb[3])
end

# ---- 渲染单帧(注意: 内层循环保持串行, 外层按帧并行)----
function render_frame(c::ComplexF64)
    img = Matrix{RGB{N0f8}}(undef, H, W)
    for j in 1:H
        y = ys[j]
        for i in 1:W
            z = complex(xs[i], y)
            n = 0
            while n < MAX_ITER && abs2(z) <= ESCAPE_R2
                z = z * z + c
                n += 1
            end
            if n == MAX_ITER
                img[j, i] = RGB{N0f8}(0, 0, 0)
            else
                nu = n + 1 - log2(log(abs(z)))
                img[j, i] = palette((nu / MAX_ITER)^0.4)
            end
        end
    end
    return img
end

# ---- 修正 GIF: ImageMagick.jl 写 GIF 无法指定帧延迟和循环次数 ----
# 按 GIF 块结构遍历, 只改真正的 GCE(帧延迟), 并确保有 NETSCAPE 循环扩展
function fix_gif!(path::AbstractString, delay_cs::Int)
    data = read(path)
    packed = data[11]                          # 逻辑屏幕描述符的 packed 字节
    o = 13                                     # 跳过 "GIF89a" + 逻辑屏幕描述符
    (packed & 0x80) != 0 && (o += 3 * 2 ^ ((packed & 0x07) + 1))
    if !occursin("NETSCAPE2.0", String(copy(data)))
        netscape = UInt8[0x21, 0xFF, 0x0B]
        append!(netscape, codeunits("NETSCAPE2.0"))
        append!(netscape, UInt8[0x03, 0x01, 0x00, 0x00, 0x00])  # 循环 0 = 无限
        splice!(data, (o + 1):(o), netscape)   # 在第一个块前插入
    end
    fixed = 0
    while o < length(data)
        b = data[o + 1]
        if b == 0x3B                            # 文件结束
            break
        elseif b == 0x21                        # 扩展块
            data[o + 2] == 0xF9 && begin        # Graphic Control Extension
                data[o + 5] = delay_cs % UInt8           # 延迟低字节
                data[o + 6] = (delay_cs >> 8) % UInt8    # 延迟高字节
                fixed += 1
            end
            o += 2
            while data[o + 1] != 0x00           # 跳过子块
                o += 1 + data[o + 1]
            end
            o += 1
        elseif b == 0x2C                        # 图像描述符
            packed2 = data[o + 10]
            o += 10
            (packed2 & 0x80) != 0 && (o += 3 * 2 ^ ((packed2 & 0x07) + 1))
            o += 1                              # LZW 最小码长
            while data[o + 1] != 0x00
                o += 1 + data[o + 1]
            end
            o += 1
        else
            error("未知的 GIF 块 0x$(string(b, base = 16)) @ 偏移 $o")
        end
    end
    write(path, data)
    return fixed
end

# ---- 主流程: 按帧多线程渲染 ----
t0 = time()
frames = Vector{Matrix{RGB{N0f8}}}(undef, NFRAMES)
Threads.@threads for k in 1:NFRAMES
    α = 2π * (k - 1) / NFRAMES
    frames[k] = render_frame(complex(ORBIT_R * cos(α), ORBIT_R * sin(α)))
    (k % 30 == 0) && println("  已渲染 $k/$NFRAMES 帧")
end
println("帧渲染完成, 耗时 $(round(time() - t0; digits = 1)) 秒")

# ---- 合成 GIF: 有 ffmpeg 用 ffmpeg, 否则用 ImageMagick.jl ----
t1 = time()
if Sys.which("ffmpeg") !== nothing
    mkpath(OUTDIR)
    for (k, img) in enumerate(frames)
        save(joinpath(OUTDIR, @sprintf("frame_%04d.png", k)), img)
    end
    run(`ffmpeg -y -loglevel error -framerate $FPS -i $OUTDIR/frame_%04d.png -loop 0 $GIF_PATH`)
    rm(OUTDIR; recursive = true)
else
    stack = cat(frames...; dims = 3)
    save(GIF_PATH, stack)
    n = fix_gif!(GIF_PATH, div(100, FPS))
    println("  已修正 $n 个帧延迟 → $(div(100, FPS)) cs ($(div(100, div(100, FPS))) fps), 并确保无限循环")
end
println("GIF 已保存: $GIF_PATH  ($(NFRAMES) 帧, $(W)×$(H), 合成耗时 $(round(time() - t1; digits = 1)) 秒)")
