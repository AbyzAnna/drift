# characters.py — builds Pip's characters in 3D and renders them as layered parts for the app.
# Run with Blender's Python module:  python characters.py <out_dir> [species ...]
# Every part is rendered with the same orthographic camera, so all images line up exactly;
# the app rotates them around the pivots written to manifest.json (in Pip units, 1 BU = 10 units).

import bpy, math, json, os, sys
from mathutils import Vector, Euler

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
ONLY = sys.argv[2:]
PX = int(os.environ.get("PX", "300"))                   # image size
ORTHO = 6.0                # BU across the image
CAM_Z = 2.8                # image centre height
SAMPLES = int(os.environ.get("SAMPLES", "96"))

# ---------------------------------------------------------------- helpers

def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def col(h, a=1.0):
    return (lin((h >> 16) & 255), lin((h >> 8) & 255), lin(h & 255), a)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.resolution_x = PX
    sc.render.resolution_y = PX
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.cycles.max_bounces = 6
    cam = bpy.data.cameras.new("cam")
    cam.type = 'ORTHO'
    cam.ortho_scale = ORTHO
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = (0, -20, CAM_Z)
    co.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = co
    # studio lighting: soft key from the upper left, cool fill, warm rim lights behind
    lights = [
        ("key", (-4, -6, 7), 420, 5, 0xFFF4E8),
        ("fill", (6, -5, 3), 120, 6, 0xDDE6FF),
        ("rimL", (-4.5, 5, 4.5), 420, 3, 0xFFDDB0),
        ("rimR", (4.5, 5, 4.5), 420, 3, 0xFFDDB0),
        ("top", (0, 1, 9), 120, 4, 0xFFFFFF),
    ]
    for name, loc, energy, size, c in lights:
        l = bpy.data.lights.new(name, 'AREA')
        l.energy = energy
        l.size = size
        l.color = col(c)[:3]
        lo = bpy.data.objects.new(name, l)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 2.4)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.collection.objects.link(lo)
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = col(0xC9D2E6)
    bg.inputs[1].default_value = 0.35

def node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n

def mat_plush(name, base, marks=(), sheen=1.0, rough=0.62, sss=0.08, bump=0.25):
    """Plush fur: velvety sheen, a touch of subsurface, fine fibre bump. `marks` are soft colour patches
    given in object space: (centre, radius, colour, softness, axis scale)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    colour = None
    rgb = node(nt, "ShaderNodeRGB")
    rgb.outputs[0].default_value = col(base)
    colour = rgb.outputs[0]
    for (c, r, mc, soft, scale) in marks:
        sub = nt.nodes.new("ShaderNodeVectorMath"); sub.operation = 'SUBTRACT'
        sub.inputs[1].default_value = c
        nt.links.new(tc.outputs["Object"], sub.inputs[0])
        mul = nt.nodes.new("ShaderNodeVectorMath"); mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = scale
        nt.links.new(sub.outputs[0], mul.inputs[0])
        ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = 'LENGTH'
        nt.links.new(mul.outputs[0], ln.inputs[0])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = r * (1 - soft)
        mr.inputs["From Max"].default_value = r
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        nt.links.new(ln.outputs["Value"], mr.inputs["Value"])
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'
        nt.links.new(mr.outputs[0], mix.inputs["Factor"])
        nt.links.new(colour, mix.inputs[6])
        mix.inputs[7].default_value = col(mc)
        colour = mix.outputs[2]
    # subtle fibre variation
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 180
    noise.inputs["Detail"].default_value = 6
    vary = nt.nodes.new("ShaderNodeMix"); vary.data_type = 'RGBA'; vary.blend_type = 'MULTIPLY'
    vary.inputs["Factor"].default_value = 0.12
    nt.links.new(colour, vary.inputs[6])
    nt.links.new(noise.outputs["Color"], vary.inputs[7])
    nt.links.new(vary.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Sheen Weight"].default_value = sheen
    bsdf.inputs["Sheen Roughness"].default_value = 0.35
    bsdf.inputs["Sheen Tint"].default_value = (1, 1, 1, 1)
    bsdf.inputs["Subsurface Weight"].default_value = sss
    bsdf.inputs["Subsurface Radius"].default_value = (0.3, 0.2, 0.15)
    bsdf.inputs["Subsurface Scale"].default_value = 0.05
    nt.links.new(colour, bsdf.inputs["Subsurface Radius"]) if False else None
    # hairs get a real hair shader in the same colours (white fur stays white and glows at the rim)
    hb = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    hb.parametrization = 'COLOR'
    bright = nt.nodes.new("ShaderNodeMix"); bright.data_type = 'RGBA'; bright.blend_type = 'SCREEN'
    bright.inputs["Factor"].default_value = 0.25
    nt.links.new(vary.outputs[2], bright.inputs[6])
    bright.inputs[7].default_value = (1, 1, 1, 1)
    nt.links.new(bright.outputs[2], hb.inputs["Color"])
    hb.inputs["Roughness"].default_value = 0.35
    hb.inputs["Radial Roughness"].default_value = 0.6
    hb.inputs["Coat"].default_value = 0.3
    info = nt.nodes.new("ShaderNodeHairInfo")
    mixs = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(info.outputs["Is Strand"], mixs.inputs[0])
    nt.links.new(bsdf.outputs[0], mixs.inputs[1])
    nt.links.new(hb.outputs[0], mixs.inputs[2])
    nt.links.new(mixs.outputs[0], out.inputs[0])
    bn = nt.nodes.new("ShaderNodeBump")
    bn.inputs["Strength"].default_value = bump
    bn.inputs["Distance"].default_value = 0.01
    fib = nt.nodes.new("ShaderNodeTexNoise")
    fib.inputs["Scale"].default_value = 420
    fib.inputs["Detail"].default_value = 2
    nt.links.new(fib.outputs["Fac"], bn.inputs["Height"])
    nt.links.new(bn.outputs["Normal"], bsdf.inputs["Normal"])
    return m

def mat_gloss(name, c, rough=0.12, coat=1.0, emit=None, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = col(c)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.03
    b.inputs["Metallic"].default_value = metallic
    if emit is not None:
        b.inputs["Emission Color"].default_value = col(emit)
        b.inputs["Emission Strength"].default_value = 6.0
    return m

def mat_eye(name, iris_top, iris_bottom):
    """Anime-style eye: deep iris graded from dark at the top to lighter at the bottom, under a glossy coat."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1.0
    mr.inputs["From Max"].default_value = 1.0
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.15
    ramp.color_ramp.elements[0].color = col(iris_bottom)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = col(iris_top)
    nt.links.new(mr.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.25
    b.inputs["Coat Weight"].default_value = 1.0
    b.inputs["Coat Roughness"].default_value = 0.02
    return m

def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob

def meta(name, elems, mat=None, res=0.035, threshold=0.6):
    """Organic sculpted shape from soft ellipsoids (centre, half-size, rotation degrees). Converted to a mesh."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = threshold
    for e in elems:
        c, size = e[0], e[1]
        rot = e[2] if len(e) > 2 else (0, 0, 0)
        stiff = e[3] if len(e) > 3 else 2.0
        el = mb.elements.new(type='ELLIPSOID')
        el.co = c
        el.radius = 1.0
        el.size_x, el.size_y, el.size_z = [v * 1.55 for v in size]
        el.stiffness = stiff
        el.rotation = Euler([math.radians(a) for a in rot]).to_quaternion()
    ob = link(bpy.data.objects.new(name, mb))
    bpy.context.view_layer.update()
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    bpy.ops.object.shade_smooth()
    if mat:
        ob.data.materials.append(mat)
    return ob

def sphere(name, c, size, mat, rot=(0, 0, 0), seg=40):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1, location=c)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    bpy.ops.object.shade_smooth()
    ob.data.materials.append(mat)
    return ob

def fur(ob, count, length, color_mat_index=0, droop=0.35, children=6, radius=0.0028, rough=0.02, vgroup=None, clump=0.0, align=None):
    if os.environ.get("NOFUR"):
        return None
    mod = ob.modifiers.new("fur", 'PARTICLE_SYSTEM')
    ps = ob.particle_systems[-1].settings
    ps.type = 'HAIR'
    ps.count = count
    ps.use_advanced_hair = True
    ps.normal_factor = length                 # with advanced hair, emission speed sets the hair length
    ps.object_align_factor = tuple(a * length for a in align) if align else (0, 0, -droop * length)
    ps.factor_random = 0.3 * length
    ps.material = color_mat_index + 1
    ps.child_type = 'INTERPOLATED' if children else 'NONE'
    ps.child_percent = children
    ps.rendered_child_count = children
    ps.child_radius = 0.03
    ps.roughness_1 = rough
    ps.roughness_1_size = 0.4
    ps.roughness_endpoint = rough * 0.5
    ps.clump_factor = clump
    for attr, v in (("root_radius", 1.0), ("tip_radius", 0.0), ("radius_scale", radius)):
        if hasattr(ps, attr):
            setattr(ps, attr, v)
    ps.display_step = 3
    ps.render_step = 3
    if vgroup:
        ob.particle_systems[-1].vertex_group_density = vgroup
    return ps

def weight_group(ob, name, fn):
    """Vertex group with weights from a function of the vertex position."""
    vg = ob.vertex_groups.new(name=name)
    for v in ob.data.vertices:
        w = max(0.0, min(1.0, fn(v.co)))
        if w > 0:
            vg.add([v.index], w, 'REPLACE')
    return name

def surface(ob, x, z, push=0.0):
    """Point on the front of `ob` at (x, z), seen from the camera, pushed out along the normal."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    ok, loc, nrm, _ = ev.ray_cast(Vector((x, -10, z)), Vector((0, 1, 0)))
    if not ok:
        return Vector((x, -1, z)), Vector((0, -1, 0))
    return loc + nrm * push, nrm

def curve(name, pts, bevel, mat, closed=False):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (p[0], p[1], p[2], 1)
    sp.use_smooth = True
    sp.use_cyclic_u = closed
    ob = link(bpy.data.objects.new(name, cu))
    ob.data.materials.append(mat)
    return ob

def arc_on(ob, cx, cz, rx, rz, a0, a1, n=14, push=0.012):
    pts = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / (n - 1)
        p, _ = surface(ob, cx + math.cos(a) * rx, cz + math.sin(a) * rz, push)
        pts.append(p)
    return pts

def group(objs):
    return [o for o in objs if o is not None]

def render(path, visible, all_objs, shadow=()):
    """Renders only `visible`; objects in `shadow` stay in the scene (casting shadows, bouncing light)
    without being seen by the camera; everything else is left out."""
    for o in all_objs:
        o.hide_render = not (o in visible or o in shadow)
        o.visible_camera = o in visible
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

def yaw(objs, deg, pivot=(0, 0, 0)):
    from mathutils import Matrix
    R = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(deg), 4, 'Z') @ Matrix.Translation(-Vector(pivot))
    for o in objs:
        o.matrix_world = R @ o.matrix_world

# ---------------------------------------------------------------- face

def face(head, spec, matname):
    """Eyes in four moods, nose, mouth and brows placed on the head's surface."""
    ex, ez, er = spec["eye_x"], spec["eye_z"], spec["eye_r"]
    eyes = {"open": [], "closed": [], "happy": [], "surprised": []}
    eye_mat = mat_eye(matname + "_eye", spec.get("iris_top", 0x14102A), spec.get("iris_bottom", 0x4A3F9C))
    white = mat_gloss(matname + "_spark", 0xFFFFFF, emit=0xFFFFFF)
    line = mat_gloss(matname + "_line", spec.get("line", 0x2A1E26), rough=0.4, coat=0.3)
    for side in (-1, 1):
        p, n = surface(head, side * ex, ez, push=-er * 0.3)
        for mood, k in (("open", 1.0), ("surprised", 1.15)):
            e = sphere(f"eye_{mood}_{side}", p, (er * k, er * 0.55 * k, er * 1.08 * k), eye_mat)
            e.rotation_euler = n.to_track_quat('-Y', 'Z').to_euler()
            eyes[mood].append(e)
            # sparkles: a big catchlight top-left and a small one bottom-right
            front, _ = surface(head, side * ex, ez, push=0.0)
            for dx, dz, r in ((-0.42, 0.38, 0.32), (0.38, -0.36, 0.14)):
                sp = sphere(f"spark_{mood}_{side}_{dx}", (front.x + dx * er * k, front.y - er * 0.18, front.z + dz * er * k),
                            (r * er * k, r * er * 0.4 * k, r * er * k), white, seg=16)
                eyes[mood].append(sp)
            # upper lid line
            pts = arc_on(head, side * ex, ez - er * 0.1 * k, er * 1.12 * k, er * 1.12 * k, math.radians(25), math.radians(155), push=0.02)
            eyes[mood].append(curve(f"lid_{mood}_{side}", pts, er * 0.11, line))
        # closed: a gentle downward curve; happy: an upward "^" curve
        pts = arc_on(head, side * ex, ez + er * 0.35, er * 0.95, er * 0.55, math.radians(200), math.radians(340), push=0.02)
        eyes["closed"].append(curve(f"closed_{side}", pts, er * 0.12, line))
        pts = arc_on(head, side * ex, ez - er * 0.45, er * 0.9, er * 0.85, math.radians(25), math.radians(155), push=0.02)
        eyes["happy"].append(curve(f"happy_{side}", pts, er * 0.13, line))
    extras = []
    # nose
    nz = spec["nose_z"]
    p, n = surface(head, 0, nz, push=0.0)
    nose_mat = mat_gloss(matname + "_nose", spec.get("nose", 0xF0A0A4), rough=0.3, coat=0.6)
    if spec.get("beak"):
        bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=spec["beak"][0], radius2=0.01, depth=spec["beak"][1], location=p)
        nb = bpy.context.active_object
        nb.rotation_euler = (math.radians(90 + 12), 0, 0)
        nb.scale = (1, 0.75, 1)
        bpy.ops.object.shade_smooth()
        nb.data.materials.append(nose_mat)
    else:
        nw = spec.get("nose_w", 0.09)
        bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=nw, radius2=0.0, depth=nw * 0.9, location=p + n * 0.01)
        nb = bpy.context.active_object
        nb.rotation_euler = (math.radians(90), math.radians(180), 0)
        sub = nb.modifiers.new("s", 'SUBSURF'); sub.levels = 3; sub.render_levels = 3
        bpy.ops.object.shade_smooth()
        nb.data.materials.append(nose_mat)
    nb.name = "nose"
    extras.append(nb)
    if spec.get("whiskers"):
        wm = mat_gloss(matname + "_wh", 0xFFFFFF, rough=0.4, coat=0.0)
        for side in (-1, 1):
            for i in range(3):
                o, _ = surface(head, side * 0.16, nz - 0.04 - i * 0.05, push=0.01)
                pts = [o, o + Vector((side * 0.3, -0.06, 0.04 - i * 0.05)), o + Vector((side * 0.62, 0.02, 0.06 - i * 0.12))]
                extras.append(curve(f"wh{side}{i}", pts, 0.0045, wm))
    if spec.get("beak"):
        return eyes, extras
    # mouth: a small "w"
    mz = spec["mouth_z"]
    mw = spec.get("mouth_w", 0.13)
    pts = []
    for i in range(17):
        u = i / 16 * 2 - 1
        z = mz + 0.045 * (math.cos(u * math.pi * 2) - 1) * 0.5 - 0.02 * (1 - u * u)
        q, _ = surface(head, u * mw, z, push=0.012)
        pts.append(q)
    extras.append(curve("mouth", pts, 0.011, line))
    return eyes, extras

# ---------------------------------------------------------------- species

SPECIES = {}

def bunny():
    fur_c = 0xF3F0EC
    head_m = mat_plush("bunny_head", fur_c, marks=[
        ((-0.66, -0.66, 2.22), 0.34, 0xF6ACB2, 0.9, (1, 1, 1.2)),
        ((0.66, -0.66, 2.22), 0.34, 0xF6ACB2, 0.9, (1, 1, 1.2)),
    ])
    body_m = mat_plush("bunny_body", fur_c)
    inner_m = mat_plush("bunny_inner", 0xBFEADA, sheen=0.6, rough=0.7)
    torso = meta("body", [
        ((0, 0, 1.0), (0.8, 0.66, 0.74)),
        ((0, -0.1, 0.82), (0.74, 0.62, 0.56)),
        ((0, 0, 1.5), (0.56, 0.5, 0.4)),
    ], body_m)
    footL = meta("footL", [((-0.38, -0.28, 0.12), (0.26, 0.36, 0.14))], body_m)
    footR = meta("footR", [((0.38, -0.28, 0.12), (0.26, 0.36, 0.14))], body_m)
    armL = meta("armL", [((-0.74, -0.24, 1.22), (0.22, 0.22, 0.4), (0, -14, 0))], body_m)
    armR = meta("armR", [((0.74, -0.24, 1.22), (0.22, 0.22, 0.4), (0, 14, 0))], body_m)
    head = meta("head", [
        ((0, 0, 2.62), (1.04, 0.86, 0.8)),
        ((-0.58, -0.16, 2.36), (0.55, 0.5, 0.44)),
        ((0.58, -0.16, 2.36), (0.55, 0.5, 0.44)),
        ((0, -0.46, 2.3), (0.36, 0.32, 0.26)),
        # small fluffy tuft on top
        ((-0.1, -0.22, 3.2), (0.11, 0.09, 0.15), (0, 30, 0), 3),
        ((0.1, -0.22, 3.22), (0.1, 0.09, 0.16), (0, -25, 0), 3),
    ], head_m)
    ears = []
    for side, nm in ((-1, "earL"), (1, "earR")):
        e = meta(nm, [((side * 0.5, 0.08, 3.85), (0.32, 0.14, 0.92), (0, side * 12, 0))], body_m)
        inner = sphere(nm + "_in", (side * 0.51, -0.1, 3.83), (0.14, 0.05, 0.74), inner_m, rot=(0, side * 12, 0))
        ears.append((nm, [e, inner]))
    # fine fuzz, kept clear of the face and the inside of the ears
    face_clear = weight_group(head, "fuzz", lambda c: 0.0 if (c.y < -0.35 and 2.0 < c.z < 2.85 and abs(c.x) < 0.8) else 1.0)
    for ob, cnt, ln, vg in ((torso, 5000, 0.022, None), (footL, 300, 0.018, None), (footR, 300, 0.018, None),
                            (armL, 800, 0.02, None), (armR, 800, 0.02, None), (head, 6000, 0.02, face_clear)):
        fur(ob, cnt, ln, vgroup=vg)
    for nm, (e, inner) in ears:
        fur(e, 1200, 0.016, droop=0.1, vgroup=weight_group(e, "back", lambda c: 1.0 if c.y > -0.02 else 0.0))
    spec = dict(eye_x=0.44, eye_z=2.54, eye_r=0.23, nose_z=2.32, mouth_z=2.2, nose=0xF29A9E, nose_w=0.09,
                iris_top=0x15122E, iris_bottom=0x5B4FB0, line=0x3A2630)
    return dict(body=[torso], feet=([footL], [footR]), arms=([armL], [armR]), head=head, ears=[e for e in ears],
                spec=spec, pivots=dict(neck=(0, 1.75), shoulderL=(-0.68, 1.55), shoulderR=(0.68, 1.55),
                                       earL=(-0.45, 3.1), earR=(0.45, 3.1), footL=(-0.38, 0.1), footR=(0.38, 0.1)),
                hat=dict(center=(0, 2.65), r=1.0, top=3.35), scarf=dict(z=1.78, rx=0.6, ry=0.52))

SPECIES["bunny"] = bunny

def mirror_elems(elems):
    return [((-c[0], c[1], c[2]), size, (r[0], -r[1], -r[2]) if r else (0, 0, 0)) + tuple(e[3:]) for e in elems
            for (c, size, r) in [(e[0], e[1], e[2] if len(e) > 2 else (0, 0, 0))]]

def limbs(name, elems, mat, fur_count, fur_len, droop=0.35):
    L = meta(name + "L", elems, mat)
    R = meta(name + "R", mirror_elems(elems), mat)
    if fur_count:
        fur(L, fur_count, fur_len, droop=droop)
        fur(R, fur_count, fur_len, droop=droop)
    return [L], [R]

def wool_cluster(name, centre, radii, n, ball, mat, seed=1):
    """Lamb's fleece: an ellipsoid covered in many soft lumps."""
    import random
    rnd = random.Random(seed)
    elems = [(centre, tuple(r * 0.82 for r in radii))]
    for i in range(n):
        u = rnd.uniform(-1, 1); a = rnd.uniform(0, 2 * math.pi)
        s = math.sqrt(1 - u * u)
        p = (centre[0] + radii[0] * s * math.cos(a), centre[1] + radii[1] * s * math.sin(a), centre[2] + radii[2] * u)
        r = ball * rnd.uniform(0.8, 1.2)
        elems.append((p, (r, r, r), (0, 0, 0), 2.5))
    return meta(name, elems, mat, res=0.03)

def penguin():
    down = mat_plush("pg_body", 0xB4B2AF, marks=[((0, -0.75, 0.95), 0.7, 0xE9E7E3, 0.8, (1, 0.6, 0.85))], sheen=1.0, rough=0.7)
    head_m = mat_plush("pg_head", 0x26262B, marks=[
        ((-0.42, -0.72, 2.36), 0.42, 0xF3F2EF, 0.45, (1.05, 0.7, 0.85)),
        ((0.42, -0.72, 2.36), 0.42, 0xF3F2EF, 0.45, (1.05, 0.7, 0.85)),
        ((0, -0.8, 1.95), 0.3, 0x3A3A40, 0.6, (1, 1, 1)),
    ], sheen=0.9, rough=0.65)
    black = mat_gloss("pg_feet", 0x1C1C20, rough=0.35, coat=0.4)
    torso = meta("body", [((0, 0, 0.98), (0.86, 0.76, 0.84)), ((0, -0.08, 0.75), (0.8, 0.7, 0.6))], down)
    head = meta("head", [((0, 0, 2.38), (0.98, 0.86, 0.84)), ((-0.45, -0.2, 2.2), (0.5, 0.46, 0.42)), ((0.45, -0.2, 2.2), (0.5, 0.46, 0.42))], head_m)
    fL = meta("footL", [((-0.34, -0.42, 0.07), (0.24, 0.3, 0.07))], black)
    fR = meta("footR", [((0.34, -0.42, 0.07), (0.24, 0.3, 0.07))], black)
    aL, aR = limbs("arm", [((-0.86, -0.08, 1.12), (0.17, 0.13, 0.46), (0, -22, 0))], down, 700, 0.035)
    fur(torso, 6500, 0.035); fur(head, 5500, 0.026, vgroup=weight_group(head, "fz", lambda c: 0.0 if (c.y < -0.45 and 2.0 < c.z < 2.6 and abs(c.x) < 0.7) else 1.0))
    spec = dict(eye_x=0.4, eye_z=2.42, eye_r=0.15, nose_z=2.2, mouth_z=1.95, nose=0x18181C, beak=(0.2, 0.3),
                iris_top=0x050507, iris_bottom=0x23232C, line=0x0A0A0C)
    return dict(body=[torso], feet=([fL], [fR]), arms=(aL, aR), head=head, ears=[], spec=spec,
                pivots=dict(neck=(0, 1.6), shoulderL=(-0.78, 1.45), shoulderR=(0.78, 1.45), footL=(-0.34, 0.07), footR=(0.34, 0.07)),
                hat=dict(center=(0, 2.45), r=0.95, top=3.15), scarf=dict(z=1.62, rx=0.64, ry=0.56), no_mouth=True)

def lamb():
    wool_m = mat_plush("lb_wool", 0xF1ECE4, sheen=1.0, rough=0.75, bump=0.6)
    face_m = mat_plush("lb_face", 0xF6F2EC, marks=[((-0.55, -0.62, 2.18), 0.28, 0xF6B5B8, 0.9, (1, 1, 1.2)), ((0.55, -0.62, 2.18), 0.28, 0xF6B5B8, 0.9, (1, 1, 1.2))])
    pink = mat_plush("lb_ear_in", 0xF2A9AC, sheen=0.5, rough=0.7)
    hoof = mat_gloss("lb_hoof", 0x7E746E, rough=0.4, coat=0.3)
    torso = wool_cluster("body", (0, 0, 1.12), (0.78, 0.66, 0.6), 70, 0.17, wool_m, seed=3)
    head = meta("head", [((0, 0, 2.3), (0.72, 0.66, 0.74)), ((0, -0.38, 2.08), (0.42, 0.36, 0.36))], face_m)
    crown = wool_cluster("crown", (0, -0.05, 2.78), (0.66, 0.55, 0.3), 34, 0.13, wool_m, seed=5)
    legs = []
    for nm, x in (("footL", -0.36), ("footR", 0.36)):
        lg = meta(nm, [((x, -0.15, 0.32), (0.13, 0.13, 0.3))], face_m)
        hf = sphere(nm + "_hoof", (x, -0.15, 0.06), (0.14, 0.14, 0.08), hoof)
        legs.append([lg, hf])
    aL, aR = limbs("arm", [((-0.66, -0.22, 1.05), (0.17, 0.17, 0.3), (0, -10, 0))], wool_m, 0, 0)
    ears = []
    for side, nm in ((-1, "earL"), (1, "earR")):
        e = meta(nm, [((side * 0.86, -0.02, 2.42), (0.36, 0.13, 0.16), (0, side * -18, 0))], face_m)
        inner = sphere(nm + "_in", (side * 0.88, -0.1, 2.41), (0.25, 0.04, 0.09), pink, rot=(0, side * -18, 0))
        ears.append((nm, [e, inner]))
    fur(head, 3500, 0.015, vgroup=weight_group(head, "fz", lambda c: 0.0 if (c.y < -0.3 and 1.9 < c.z < 2.55 and abs(c.x) < 0.6) else 1.0))
    fur(torso, 2500, 0.02, droop=0.1); fur(crown, 1200, 0.02, droop=0.1)
    spec = dict(eye_x=0.31, eye_z=2.36, eye_r=0.15, nose_z=2.12, mouth_z=1.99, nose=0xF09AA6, nose_w=0.07,
                iris_top=0x1A120E, iris_bottom=0x4A3426, line=0x3A2A26)
    return dict(body=[torso], feet=tuple(legs), arms=(aL, aR), head=head, head_extra=[crown], ears=ears, spec=spec,
                pivots=dict(neck=(0, 1.6), shoulderL=(-0.6, 1.3), shoulderR=(0.6, 1.3), earL=(-0.62, 2.45), earR=(0.62, 2.45),
                            footL=(-0.36, 0.5), footR=(0.36, 0.5)),
                hat=dict(center=(0, 2.4), r=0.8, top=3.02), scarf=dict(z=1.68, rx=0.56, ry=0.5))

def otter():
    brown = 0x6E4A33
    body_m = mat_plush("ot_body", brown, marks=[((0, -0.7, 1.25), 0.55, 0xE3D2B8, 0.7, (1, 0.6, 0.9))], sheen=0.8, rough=0.55)
    head_m = mat_plush("ot_head", brown, marks=[((0, -0.65, 2.12), 0.62, 0xEADCC6, 0.55, (0.9, 0.8, 1.25)),
                                                ((-0.5, -0.6, 2.0), 0.24, 0xE8B7AE, 0.9, (1, 1, 1.2)), ((0.5, -0.6, 2.0), 0.24, 0xE8B7AE, 0.9, (1, 1, 1.2))],
                        sheen=0.8, rough=0.55)
    dark = mat_plush("ot_dark", 0x3E2618, sheen=0.5)
    torso = meta("body", [((0, 0, 1.0), (0.8, 0.7, 0.85)), ((0, -0.05, 0.72), (0.76, 0.66, 0.55))], body_m)
    head = meta("head", [((0, 0, 2.3), (0.92, 0.8, 0.74)), ((0, -0.42, 2.06), (0.5, 0.42, 0.34))], head_m)
    ears_e = []
    for side, nm in ((-1, "earL"), (1, "earR")):
        e = meta(nm, [((side * 0.74, 0.05, 2.78), (0.19, 0.12, 0.17))], body_m)
        dot = sphere(nm + "_in", (side * 0.74, -0.05, 2.78), (0.09, 0.03, 0.08), dark)
        ears_e.append((nm, [e, dot]))
    fL = meta("footL", [((-0.38, -0.32, 0.1), (0.24, 0.3, 0.11))], dark)
    fR = meta("footR", [((0.38, -0.32, 0.1), (0.24, 0.3, 0.11))], dark)
    aL, aR = limbs("arm", [((-0.38, -0.62, 1.32), (0.17, 0.17, 0.28), (40, 0, -20))], body_m, 500, 0.02)
    fur(torso, 6000, 0.022); fur(head, 5000, 0.02, vgroup=weight_group(head, "fz", lambda c: 0.0 if (c.y < -0.35 and 1.85 < c.z < 2.55 and abs(c.x) < 0.6) else 1.0))
    spec = dict(eye_x=0.4, eye_z=2.38, eye_r=0.155, nose_z=2.1, mouth_z=1.95, nose=0x8E5A4C, nose_w=0.1,
                iris_top=0x0E0806, iris_bottom=0x3A2418, line=0x22140C, whiskers=True)
    return dict(body=[torso], feet=([fL], [fR]), arms=(aL, aR), head=head, ears=ears_e, spec=spec,
                pivots=dict(neck=(0, 1.62), shoulderL=(-0.42, 1.5), shoulderR=(0.42, 1.5), earL=(-0.74, 2.7), earR=(0.74, 2.7),
                            footL=(-0.38, 0.1), footR=(0.38, 0.1)),
                hat=dict(center=(0, 2.35), r=0.9, top=3.0), scarf=dict(z=1.66, rx=0.62, ry=0.54))

def seal():
    white = 0xF2F4F7
    body_m = mat_plush("sl_body", white, sheen=1.0, rough=0.7)
    head_m = mat_plush("sl_head", white, marks=[((-0.2, -0.85, 2.05), 0.24, 0x9C948D, 0.5, (1, 1, 1.15)), ((0.2, -0.85, 2.05), 0.24, 0x9C948D, 0.5, (1, 1, 1.15)),
                                                ((-0.55, -0.6, 2.05), 0.22, 0xF2C2C6, 0.9, (1, 1, 1.2)), ((0.55, -0.6, 2.05), 0.22, 0xF2C2C6, 0.9, (1, 1, 1.2))],
                        sheen=1.0, rough=0.7)
    torso = meta("body", [((0, 0, 0.92), (1.02, 0.86, 0.86)), ((0, -0.05, 0.62), (1.0, 0.82, 0.55))], body_m)
    head = meta("head", [((0, 0, 2.15), (0.98, 0.86, 0.86)), ((0, -0.5, 2.0), (0.42, 0.36, 0.3))], head_m)
    aL, aR = limbs("arm", [((-0.98, -0.25, 0.62), (0.26, 0.12, 0.38), (0, 55, 0))], body_m, 400, 0.02)
    fur(torso, 7000, 0.032); fur(head, 6000, 0.028, vgroup=weight_group(head, "fz", lambda c: 0.0 if (c.y < -0.4 and 1.8 < c.z < 2.5 and abs(c.x) < 0.7) else 1.0))
    spec = dict(eye_x=0.42, eye_z=2.3, eye_r=0.23, nose_z=2.12, mouth_z=1.88, nose=0x18120F, nose_w=0.1,
                iris_top=0x050404, iris_bottom=0x2A2220, line=0x0E0A08, whiskers=True)
    return dict(body=[torso], feet=([], []), arms=(aL, aR), head=head, ears=[], spec=spec,
                pivots=dict(neck=(0, 1.45), shoulderL=(-0.85, 0.85), shoulderR=(0.85, 0.85)),
                hat=dict(center=(0, 2.2), r=0.95, top=2.98), scarf=dict(z=1.45, rx=0.72, ry=0.62))

def hedgehog():
    face_m = mat_plush("hh_face", 0xE9E0D3, marks=[((-0.36, -0.7, 2.18), 0.24, 0x8C7563, 0.7, (1, 1, 1.1)), ((0.36, -0.7, 2.18), 0.24, 0x8C7563, 0.7, (1, 1, 1.1)),
                                                   ((0, -0.95, 1.95), 0.26, 0x9C8573, 0.7, (1, 1, 1)),
                                                   ((-0.5, -0.55, 1.92), 0.2, 0xF2B6B4, 0.9, (1, 1, 1.2)), ((0.5, -0.55, 1.92), 0.2, 0xF2B6B4, 0.9, (1, 1, 1.2))],
                       sheen=0.9, rough=0.7)
    body_m = mat_plush("hh_body", 0xE5DACB, sheen=0.9, rough=0.7)
    pink = mat_gloss("hh_pink", 0xD9A49A, rough=0.5, coat=0.2)
    torso = meta("body", [((0, 0, 0.92), (0.82, 0.72, 0.8)), ((0, -0.05, 0.66), (0.8, 0.7, 0.52))], body_m)
    head = meta("head", [((0, 0.05, 2.15), (0.86, 0.78, 0.74)), ((0, -0.62, 1.98), (0.3, 0.32, 0.24))], face_m)
    # a dome of quills over the back and top of the head
    shell = meta("quills", [((0, 0.32, 2.2), (0.95, 0.72, 0.88)), ((0, 0.3, 1.2), (0.9, 0.7, 0.95))], body_m)
    qm = mat_quill("hh_quill")
    shell.data.materials.append(qm)
    vg = weight_group(shell, "back", lambda c: 1.0 if (c.y > -0.15 + 0.25 * max(0, 2.3 - c.z) and c.z > 0.5) else 0.0)
    ps = fur(shell, 9000, 0.12, color_mat_index=1, children=0, radius=0.009, rough=0.0, vgroup=vg, align=(0, 1.1, 0.55))
    if ps is not None:
        ps.factor_random = 0.08
    ears = []
    for side, nm in ((-1, "earL"), (1, "earR")):
        e = sphere(nm, (side * 0.62, -0.1, 2.72), (0.17, 0.07, 0.15), pink)
        ears.append((nm, [e]))
    fL = meta("footL", [((-0.34, -0.36, 0.07), (0.2, 0.24, 0.07))], pink)
    fR = meta("footR", [((0.34, -0.36, 0.07), (0.2, 0.24, 0.07))], pink)
    aL, aR = limbs("arm", [((-0.32, -0.66, 1.18), (0.13, 0.12, 0.13))], pink, 0, 0)
    fur(head, 4000, 0.022, vgroup=weight_group(head, "fz", lambda c: 0.0 if (c.y < -0.4 and 1.8 < c.z < 2.45 and abs(c.x) < 0.6) else 1.0))
    fur(torso, 4500, 0.025)
    spec = dict(eye_x=0.34, eye_z=2.2, eye_r=0.145, nose_z=1.99, mouth_z=1.84, nose=0x1A1210, nose_w=0.085,
                iris_top=0x050404, iris_bottom=0x2A1E18, line=0x1A120E, whiskers=True)
    return dict(body=[torso, shell], feet=([fL], [fR]), arms=(aL, aR), head=head, ears=ears, spec=spec,
                pivots=dict(neck=(0, 1.5), shoulderL=(-0.3, 1.25), shoulderR=(0.3, 1.25), earL=(-0.62, 2.7), earR=(0.62, 2.7),
                            footL=(-0.34, 0.07), footR=(0.34, 0.07)),
                hat=dict(center=(0, 2.25), r=0.85, top=2.95), scarf=dict(z=1.52, rx=0.62, ry=0.55))

def mat_quill(name):
    """Hedgehog quill: dark at the root, a cream band, a brown band and a pale tip."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    info = nt.nodes.new("ShaderNodeHairInfo")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = 'EASE'
    cr.elements[0].position = 0.0; cr.elements[0].color = col(0x3A2B21)
    cr.elements[1].position = 1.0; cr.elements[1].color = col(0xF6F0E6)
    for pos, c in ((0.25, 0xE7DCC8), (0.5, 0xE3D6C1), (0.62, 0x4E3A2C), (0.82, 0x5C4433)):
        e = cr.elements.new(pos); e.color = col(c)
    nt.links.new(info.outputs["Intercept"], ramp.inputs[0])
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Roughness"].default_value = 0.35
    b.inputs["Coat Weight"].default_value = 0.3
    nt.links.new(ramp.outputs[0], b.inputs["Base Color"])
    nt.links.new(b.outputs[0], out.inputs[0])
    return m

SPECIES["penguin"] = penguin
SPECIES["lamb"] = lamb
SPECIES["otter"] = otter
SPECIES["seal"] = seal
SPECIES["hedgehog"] = hedgehog

# ---------------------------------------------------------------- outfits

def mat_knit(name, c1, c2, stripes=True):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    if stripes:
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = 'BANDS'; wave.bands_direction = 'X'
        wave.wave_profile = 'SAW'
        wave.inputs["Scale"].default_value = 1.7
        nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMath"); mr.operation = 'GREATER_THAN'; mr.inputs[1].default_value = 0.5
        nt.links.new(wave.outputs["Fac"], mr.inputs[0])
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'
        mix.inputs[6].default_value = col(c1); mix.inputs[7].default_value = col(c2)
        nt.links.new(mr.outputs[0], mix.inputs["Factor"])
        nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    else:
        b.inputs["Base Color"].default_value = col(c1)
    # knit stitches: vertical rows of little bumps
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 55
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 1.0, 0.55)
    nt.links.new(tc.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs[0], v.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6
    nt.links.new(v.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.85
    b.inputs["Sheen Weight"].default_value = 0.6
    return m

def outfits(C):
    """3D accessories sized to this character. Returns name -> objects, and which part they ride on."""
    hc, hr, top = C["hat"]["center"], C["hat"]["r"], C["hat"]["top"]
    sz, srx, sry = C["scarf"]["z"], C["scarf"]["rx"], C["scarf"]["ry"]
    out = {}
    # knitted scarves: a thick ring around the neck plus a tail hanging from a knot
    def scarf(name, c1, c2):
        m = mat_knit(name + "_m", c1, c2)
        ring = meta(name, [((math.cos(a) * srx, math.sin(a) * sry - 0.05, sz + 0.03 * math.sin(a)), (0.2, 0.2, 0.17))
                           for a in [i * 2 * math.pi / 14 for i in range(14)]], m, threshold=0.5)
        tail = meta(name + "_tail", [((srx * 0.55, -sry - 0.12, sz - 0.3), (0.17, 0.08, 0.36), (0, -8, 0)),
                                    ((srx * 0.6, -sry - 0.14, sz - 0.62), (0.17, 0.07, 0.2), (0, -8, 0))], m)
        knot = sphere(name + "_knot", (srx * 0.5, -sry - 0.1, sz - 0.02), (0.15, 0.12, 0.14), m)
        return [ring, tail, knot]
    out["scarf_snow"] = ("body", scarf("scarf_snow", 0x3E7BD6, 0x4FC9C0))
    out["scarf_autumn"] = ("body", scarf("scarf_autumn", 0xE39A3B, 0xC8642A))
    # knitted beanie with a pompom
    bm = mat_knit("beanie_m", 0xF07C8E, 0xF07C8E, stripes=False)
    band = mat_knit("band_m", 0xFFF6EE, 0xFFF6EE, stripes=False)
    beanie = meta("beanie", [((hc[0], -0.02, top - 0.02), (hr * 0.76, hr * 0.72, 0.46))], bm)
    brim = meta("brim", [((math.cos(a) * hr * 0.74, math.sin(a) * hr * 0.68 - 0.03, top - 0.24), (0.15, 0.15, 0.12))
                         for a in [i * 2 * math.pi / 16 for i in range(16)]], band, threshold=0.5)
    pom = sphere("pom", (hc[0], -0.02, top + 0.46), (0.19, 0.19, 0.19), band)
    fur(pom, 500, 0.05, droop=0.0)
    out["beanie"] = ("head", [beanie, brim, pom])
    # flower crown
    petal = {k: mat_gloss("petal_" + str(k), k, rough=0.5, coat=0.2) for k in (0xFFD166, 0xFF8FA3, 0xB79CFF, 0x7FD0FF, 0xFFFFFF)}
    centre = mat_gloss("fcentre", 0xF2B33D, rough=0.6, coat=0.1)
    crown = []
    for i, k in enumerate((0xFFD166, 0xFF8FA3, 0xB79CFF, 0x7FD0FF, 0xFF8FA3)):
        a = math.radians(150 - i * 30)
        c = (math.cos(a) * hr * 0.75, -0.25, hc[1] + math.sin(a) * hr * 0.62 + 0.25)
        for j in range(5):
            b = j * 2 * math.pi / 5
            crown.append(sphere(f"cp{i}{j}", (c[0] + math.cos(b) * 0.09, c[1] - 0.02, c[2] + math.sin(b) * 0.09), (0.075, 0.03, 0.075), petal[k], seg=16))
        crown.append(sphere(f"cc{i}", (c[0], c[1] - 0.05, c[2]), (0.05, 0.03, 0.05), centre, seg=12))
    out["crown"] = ("head", crown)
    # sprout
    green = mat_gloss("sprout_m", 0x7CC95A, rough=0.5, coat=0.2)
    stem = curve("stem", [(0, 0, top - 0.05), (0.03, 0, top + 0.18), (0.0, 0, top + 0.36)], 0.025, green)
    lv = [sphere("leafL", (-0.13, 0, top + 0.42), (0.14, 0.04, 0.07), green, rot=(0, 25, 0)),
          sphere("leafR", (0.13, 0, top + 0.42), (0.14, 0.04, 0.07), green, rot=(0, -25, 0))]
    out["sprout"] = ("head", [stem] + lv)
    # sakura hair clip
    pink = mat_gloss("sakura_m", 0xFFC2D6, rough=0.5, coat=0.2)
    clip = []
    cc = (hr * 0.55, -0.55, hc[1] + hr * 0.45)
    for j in range(5):
        b = j * 2 * math.pi / 5 + 0.3
        clip.append(sphere(f"sk{j}", (cc[0] + math.cos(b) * 0.1, cc[1], cc[2] + math.sin(b) * 0.1), (0.085, 0.03, 0.085), pink, seg=16))
    clip.append(sphere("skc", (cc[0], cc[1] - 0.03, cc[2]), (0.045, 0.03, 0.045), mat_gloss("skc_m", 0xE0618C), seg=12))
    out["clip"] = ("head", clip)
    # autumn leaf beret
    leafm = mat_gloss("leafhat_m", 0xE07A2E, rough=0.6, coat=0.1)
    out["leafhat"] = ("head", [sphere("leafhat", (0.15, -0.05, top - 0.02), (0.42, 0.42, 0.06), leafm, rot=(10, -14, 30))])
    return out

# ---------------------------------------------------------------- build & render

def build(name):
    reset()
    C = SPECIES[name]()
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            print("DIM", o.name, [round(x, 2) for x in o.dimensions], [round(x, 2) for x in o.location], len(o.data.vertices))
    eyes, extras = face(C["head"], C["spec"], name)
    fits = outfits(C)
    # turn the head a little toward the right of the screen; the app mirrors it for the other way
    head_objs = [C["head"]] + C.get("head_extra", []) + [o for v in eyes.values() for o in v] + extras + [o for _, objs in C["ears"] for o in objs]
    hat_objs = [o for part, objs in fits.values() if part == "head" for o in objs]
    piv = Vector((0, 0, C["pivots"]["neck"][1]))
    yaw(head_objs + hat_objs, -12, piv)
    yaw(C["body"] + [o for part, objs in fits.values() if part == "body" for o in objs], -6, Vector((0, 0, 0)))

    all_objs = [o for o in bpy.context.scene.objects if o.type in ('MESH', 'CURVE')]
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    face_base = [C["head"]] + C.get("head_extra", []) + extras
    passes = {
        "body": C["body"],
        "footL": C["feet"][0], "footR": C["feet"][1],
        "armL": C["arms"][0], "armR": C["arms"][1],
        "head_open": face_base + eyes["open"],
        "head_closed": face_base + eyes["closed"],
        "head_happy": face_base + eyes["happy"],
        "head_surprised": face_base + eyes["surprised"],
    }
    for nm, objs in C["ears"]:
        passes[nm] = objs
    for nm, (_, objs) in fits.items():
        passes["fit_" + nm] = objs
    # hide alternate eye sets from shadows too, so they don't darken the face
    for mood, objs in eyes.items():
        for o in objs:
            o.visible_shadow = False
    core = set(C["body"] + C["feet"][0] + C["feet"][1] + C["arms"][0] + C["arms"][1] + face_base + eyes["open"]
               + [o for _, objs in C["ears"] for o in objs])
    passes = {k: v for k, v in passes.items() if v}
    for nm, objs in passes.items():
        if ONLY_PASSES and nm not in ONLY_PASSES:
            continue
        extra = set(fits[nm[4:]][1]) if nm.startswith("fit_") else set()
        render(os.path.join(d, nm + ".png"), set(objs), all_objs)
    if os.environ.get("DEBUG"):
        for o in bpy.context.scene.objects:
            print("OBJ", o.name, o.type, getattr(o, "visible_camera", None), o.data.name if o.data else None)
    # full preview
    render(os.path.join(d, "_preview.png"), set(C["body"] + C["feet"][0] + C["feet"][1] + C["arms"][0] + C["arms"][1] + face_base
                                              + eyes["open"] + [o for _, objs in C["ears"] for o in objs] + fits["scarf_snow"][1]), all_objs)
    man = dict(px=PX, ortho=ORTHO * 10, center_y=CAM_Z * 10,
               pivots={k: [v[0] * 10, v[1] * 10] for k, v in C["pivots"].items()},
               hat=dict(center=[C["hat"]["center"][0] * 10, C["hat"]["center"][1] * 10], r=C["hat"]["r"] * 10),
               fits={nm: part for nm, (part, _) in fits.items()},
               ears=[nm for nm, _ in C["ears"]], parts=sorted(passes.keys()))
    with open(os.path.join(d, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)

ONLY_PASSES = [p for p in os.environ.get("PASSES", "").split(",") if p]
for nm in (ONLY or list(SPECIES.keys())):
    build(nm)
