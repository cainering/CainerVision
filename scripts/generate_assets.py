#!/usr/bin/env python3
"""Build the bundled USDZ samples and the app icon.

Friends building the app do not need to run this. The generated files are
already in the Xcode project. Re-run it only if you change the sample models.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ROOT / "CainerVision" / "Resources" / "Samples"
ICON = ROOT / "CainerVision" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

# Fixed DOS timestamp: 2026-01-01 00:00:00. Must match USDZPacker.swift.
DOS_TIME = 0
DOS_DATE = ((2026 - 1980) << 9) | (1 << 5) | 1


def pack_usdz(files: list[tuple[str, bytes]]) -> bytes:
    """Uncompressed zip whose file payloads are 64-byte aligned (USDZ)."""
    locals_blob = bytearray()
    central = bytearray()
    offset = 0
    for name, data in files:
        name_bytes = name.encode("utf-8")
        if len(data) > 0xFFFFFFFF or len(name_bytes) > 0xFFFF:
            raise ValueError("file too large for a classic zip")
        extra_len = (64 - ((offset + 30 + len(name_bytes)) % 64)) % 64
        extra = b"\x00" * extra_len
        crc = zlib.crc32(data) & 0xFFFFFFFF
        local = struct.pack(
            "<IHHHHHIIIHH",
            0x04034B50,
            20,
            0,
            0,
            DOS_TIME,
            DOS_DATE,
            crc,
            len(data),
            len(data),
            len(name_bytes),
            extra_len,
        )
        locals_blob += local + name_bytes + extra + data
        central += struct.pack(
            "<IHHHHHHIIIHHHHHII",
            0x02014B50,
            20,
            20,
            0,
            0,
            DOS_TIME,
            DOS_DATE,
            crc,
            len(data),
            len(data),
            len(name_bytes),
            0,
            0,
            0,
            0,
            0,
            offset,
        )
        central += name_bytes
        offset += len(local) + len(name_bytes) + extra_len + len(data)
    cd_offset = len(locals_blob)
    eocd = struct.pack(
        "<IHHHHIIH",
        0x06054B50,
        0,
        0,
        len(files),
        len(files),
        len(central),
        cd_offset,
        0,
    )
    return bytes(locals_blob) + bytes(central) + eocd


def assert_aligned(blob: bytes) -> None:
    import io
    import zipfile

    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        bad = zf.testzip()
        if bad:
            raise SystemExit(f"corrupt zip entry {bad}")
    offset = 0
    while offset + 4 <= len(blob):
        sig = struct.unpack_from("<I", blob, offset)[0]
        if sig != 0x04034B50:
            break
        _, _, _, _, _, _, _, comp, uncomp, name_len, extra_len = struct.unpack_from(
            "<IHHHHHIIIHH", blob, offset
        )
        data_at = offset + 30 + name_len + extra_len
        if data_at % 64 != 0:
            raise SystemExit(f"USDZ payload at {data_at} is not 64-byte aligned")
        if comp != uncomp:
            raise SystemExit("USDZ entry is compressed")
        offset = data_at + comp


def vec_fmt(values: list[tuple[float, float, float]]) -> str:
    return ", ".join(f"({x:.5f}, {y:.5f}, {z:.5f})" for x, y, z in values)


def mesh_block(name: str, positions, triangles, normals) -> str:
    counts = ", ".join(["3"] * len(triangles))
    indices = ", ".join(str(i) for tri in triangles for i in tri)
    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    zs = [p[2] for p in positions]
    extent = (
        f"({min(xs):.5f}, {min(ys):.5f}, {min(zs):.5f}), "
        f"({max(xs):.5f}, {max(ys):.5f}, {max(zs):.5f})"
    )
    return f"""
    def Mesh "{name}"
    {{
        uniform bool doubleSided = true
        int[] faceVertexCounts = [{counts}]
        int[] faceVertexIndices = [{indices}]
        point3f[] points = [{vec_fmt(positions)}]
        normal3f[] normals = [{vec_fmt(normals)}] (
            interpolation = "vertex"
        )
        float3[] extent = [{extent}]
        uniform token subdivisionScheme = "none"
    }}
"""


def material_block(name: str, color, roughness: float, metallic: float) -> str:
    r, g, b = color
    return f"""
    def Material "Mat_{name}"
    {{
        token outputs:surface.connect = </{name}/Mat_{name}/Surface.outputs:surface>
        def Shader "Surface"
        {{
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor = ({r:.4f}, {g:.4f}, {b:.4f})
            float inputs:roughness = {roughness:.3f}
            float inputs:metallic = {metallic:.3f}
            token outputs:surface
        }}
    }}
"""


def add_triangle(positions, normals, triangles, a, b, c, normal):
    start = len(positions)
    for point in (a, b, c):
        positions.append(point)
        normals.append(normal)
    triangles.append((start, start + 1, start + 2))


def cube_mesh():
    positions = []
    normals = []
    triangles = []
    s = 0.5
    faces = [
        # +Z
        ((-s, -s, s), (s, -s, s), (s, s, s), (-s, s, s), (0, 0, 1)),
        # -Z
        ((s, -s, -s), (-s, -s, -s), (-s, s, -s), (s, s, -s), (0, 0, -1)),
        # +X
        ((s, -s, s), (s, -s, -s), (s, s, -s), (s, s, s), (1, 0, 0)),
        # -X
        ((-s, -s, -s), (-s, -s, s), (-s, s, s), (-s, s, -s), (-1, 0, 0)),
        # +Y
        ((-s, s, s), (s, s, s), (s, s, -s), (-s, s, -s), (0, 1, 0)),
        # -Y
        ((-s, -s, -s), (s, -s, -s), (s, -s, s), (-s, -s, s), (0, -1, 0)),
    ]
    for a, b, c, d, normal in faces:
        add_triangle(positions, normals, triangles, a, b, c, normal)
        add_triangle(positions, normals, triangles, a, c, d, normal)
    return positions, triangles, normals


def cone_mesh(sides: int = 40):
    positions = []
    normals = []
    triangles = []
    tip = (0.0, 1.0, 0.0)
    ring = []
    for i in range(sides):
        theta = 2 * math.pi * i / sides
        ring.append((math.cos(theta) * 0.45, 0.0, math.sin(theta) * 0.45))
    for i in range(sides):
        a = ring[i]
        b = ring[(i + 1) % sides]
        edge1 = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        edge2 = (tip[0] - a[0], tip[1] - a[1], tip[2] - a[2])
        normal = _norm(_cross(edge1, edge2))
        add_triangle(positions, normals, triangles, a, b, tip, normal)
        base_normal = (0.0, -1.0, 0.0)
        add_triangle(positions, normals, triangles, a, (0.0, 0.0, 0.0), b, base_normal)
    return positions, triangles, normals


def disc_mesh(sides: int = 48, radius: float = 1.0, half_height: float = 0.12):
    positions = []
    normals = []
    triangles = []
    top = []
    bottom = []
    for i in range(sides):
        theta = 2 * math.pi * i / sides
        x = math.cos(theta) * radius
        z = math.sin(theta) * radius
        top.append((x, half_height, z))
        bottom.append((x, -half_height, z))
    for i in range(sides):
        a = top[i]
        b = top[(i + 1) % sides]
        c = bottom[(i + 1) % sides]
        d = bottom[i]
        radial = _norm(((a[0] + b[0]) * 0.5, 0.0, (a[2] + b[2]) * 0.5))
        add_triangle(positions, normals, triangles, a, d, c, radial)
        add_triangle(positions, normals, triangles, a, c, b, radial)
        add_triangle(positions, normals, triangles, a, b, (0.0, half_height, 0.0), (0.0, 1.0, 0.0))
        add_triangle(
            positions,
            normals,
            triangles,
            d,
            (0.0, -half_height, 0.0),
            c,
            (0.0, -1.0, 0.0),
        )
    return positions, triangles, normals


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _norm(v):
    length = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def wrap_xform(name: str, body: str, scale: float, spin: bool) -> str:
    if spin:
        ops = f"""
        float3 xformOp:scale = ({scale:.4f}, {scale:.4f}, {scale:.4f})
        double xformOp:rotateY.timeSamples = {{
            0: 0,
            96: 360,
        }}
        uniform token[] xformOpOrder = ["xformOp:scale", "xformOp:rotateY"]
"""
        time = """
    startTimeCode = 0
    endTimeCode = 96
    timeCodesPerSecond = 24"""
    else:
        ops = f"""
        float3 xformOp:scale = ({scale:.4f}, {scale:.4f}, {scale:.4f})
        uniform token[] xformOpOrder = ["xformOp:scale"]
"""
        time = ""
    return f"""#usda 1.0
(
    defaultPrim = "{name}"
    metersPerUnit = 1
    upAxis = "Y"{time}
)

def Xform "{name}" (
    prepend apiSchemas = ["MaterialBindingAPI"]
)
{{
    rel material:binding = </{name}/Mat_{name}>
{ops}
{body}
}}
"""


def write_sample(filename: str, usda: str) -> None:
    blob = pack_usdz([(filename.replace(".usdz", ".usda"), usda.encode("utf-8"))])
    assert_aligned(blob)
    path = SAMPLES / filename
    path.write_bytes(blob)
    print(f"wrote {path.relative_to(ROOT)} ({len(blob)} bytes)")


def build_samples() -> None:
    SAMPLES.mkdir(parents=True, exist_ok=True)
    positions, triangles, normals = cube_mesh()
    body = mesh_block("Geom", positions, triangles, normals)
    body += material_block("WarmCube", (0.86, 0.52, 0.27), 0.42, 0.08)
    write_sample("WarmCube.usdz", wrap_xform("WarmCube", body, 0.10, spin=False))

    positions, triangles, normals = cone_mesh()
    body = mesh_block("Geom", positions, triangles, normals)
    body += material_block("GuideCone", (0.93, 0.90, 0.84), 0.38, 0.0)
    write_sample("GuideCone.usdz", wrap_xform("GuideCone", body, 0.12, spin=False))

    d_pos, d_tri, d_nrm = disc_mesh()
    m_pos, m_tri, m_nrm = cube_mesh()
    # A small marker on the rim makes the spin readable.
    marker_positions = []
    marker_normals = []
    for point, normal in zip(m_pos, m_nrm):
        marker_positions.append((point[0] * 0.16 + 0.62, point[1] * 0.16 + 0.20, point[2] * 0.16))
        marker_normals.append(normal)
    body = mesh_block("Disc", d_pos, d_tri, d_nrm)
    body += mesh_block("Marker", marker_positions, m_tri, marker_normals)
    body += material_block("SpinningToken", (0.79, 0.62, 0.30), 0.28, 0.82)
    write_sample("SpinningToken.usdz", wrap_xform("SpinningToken", body, 0.06, spin=True))


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    if len(pixels) != width * height * 3:
        raise SystemExit("bad pixel buffer")
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride : (y + 1) * stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)
    print(f"wrote {path.relative_to(ROOT)} ({len(png)} bytes)")


def point_in_tri(px, py, tri) -> float:
    (x0, y0), (x1, y1), (x2, y2) = tri
    den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if abs(den) < 1e-8:
        return -1.0
    a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den
    b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den
    c = 1 - a - b
    if a < 0 or b < 0 or c < 0:
        return -1.0
    # Distance to the nearest edge, in pixels, for cheap AA.
    edges = (((x0, y0), (x1, y1)), ((x1, y1), (x2, y2)), ((x2, y2), (x0, y0)))
    dist = 1e9
    for (ax, ay), (bx, by) in edges:
        abx, aby = bx - ax, by - ay
        length = math.hypot(abx, aby) or 1.0
        dist = min(dist, abs((px - ax) * aby - (py - ay) * abx) / length)
    return dist


def build_icon() -> None:
    size = 1024
    scale = 210.0
    cx = cy = size / 2 + 8

    def project(x, y, z):
        sx = (x - z) * math.sqrt(3) / 2
        sy = (x + z) * 0.5 - y
        return (cx + sx * scale, cy + sy * scale * 0.92)

    def face(corners, color):
        projected = [project(*p) for p in corners]
        return (projected[0], projected[1], projected[2]), (projected[0], projected[2], projected[3]), color

    s = 0.72
    faces = [
        face([(-s, -s, s), (s, -s, s), (s, s, s), (-s, s, s)], (232, 201, 160)),
        face([(s, -s, -s), (s, -s, s), (s, s, s), (s, s, -s)], (201, 132, 62)),
        face([(-s, s, -s), (s, s, -s), (s, s, s), (-s, s, s)], (244, 231, 212)),
    ]
    ring_r = 392.0
    ring_w = 34.0
    dot = (cx + 250, cy + 250)

    pixels = bytearray(size * size * 3)
    for y in range(size):
        row = y * size * 3
        for x in range(size):
            r, g, b = 20, 17, 14
            dx = x - cx
            dy = y - (cy - 10)
            dist = math.hypot(dx, dy)
            ring_d = abs(dist - ring_r)
            if ring_d < ring_w / 2 + 1.2:
                coverage = max(0.0, min(1.0, (ring_w / 2 + 0.8 - ring_d)))
                r = int(r + (227 - r) * coverage)
                g = int(g + (154 - g) * coverage)
                b = int(b + (74 - b) * coverage)
            best = -1.0
            color = None
            for t0, t1, col in faces:
                for tri in (t0, t1):
                    edge = point_in_tri(x + 0.5, y + 0.5, tri)
                    if edge > best:
                        best = edge
                        color = col
            if color is not None and best >= 0:
                coverage = 1.0 if best > 1.2 else max(0.0, min(1.0, best + 0.35))
                r = int(r + (color[0] - r) * coverage)
                g = int(g + (color[1] - g) * coverage)
                b = int(b + (color[2] - b) * coverage)
            ddx = x - dot[0]
            ddy = y - dot[1]
            dot_d = math.hypot(ddx, ddy)
            if dot_d < 30:
                coverage = max(0.0, min(1.0, 28 - dot_d))
                # Dark rim then red center.
                if dot_d > 20:
                    r = int(r * (1 - coverage) + 20 * coverage)
                    g = int(g * (1 - coverage) + 16 * coverage)
                    b = int(b * (1 - coverage) + 14 * coverage)
                else:
                    inner = max(0.0, min(1.0, 20 - dot_d))
                    r = int(r + (240 - r) * inner)
                    g = int(g + (71 - g) * inner)
                    b = int(b + (62 - b) * inner)
            pixels[row + x * 3] = r
            pixels[row + x * 3 + 1] = g
            pixels[row + x * 3 + 2] = b
    ICON.parent.mkdir(parents=True, exist_ok=True)
    write_png(ICON, size, size, bytes(pixels))


if __name__ == "__main__":
    build_samples()
    build_icon()
