# Slims a Meshy USDZ/USDC (millions of triangles) down for the phone, keeping its UVs.
# Needs Python 3.10+ with: pip install pymeshlab usd-core numpy
#   python Tools/slim_model.py output.usdc slim.obj 60000
import sys, numpy as np, pymeshlab
from pxr import Usd, UsdGeom
src, out_obj, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
st = Usd.Stage.Open(src)
mesh = next(UsdGeom.Mesh(p) for p in st.Traverse() if p.IsA(UsdGeom.Mesh))
P = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
I = np.array(mesh.GetFaceVertexIndicesAttr().Get(), dtype=np.int32).reshape(-1,3)
pv = UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st')
UV = np.array(pv.Get(), dtype=np.float64); interp = pv.GetInterpolation()
idx = pv.GetIndices()
if idx: UV = UV[np.array(idx)]
print('verts', len(P), 'faces', len(I), 'uv', interp, len(UV))
assert interp == 'faceVarying'
ms = pymeshlab.MeshSet()
# write obj with wedge uvs
with open(out_obj + '.in.obj','w') as f:
    f.write('mtllib m.mtl\nusemtl Material\n')
    np.savetxt(f, P, fmt='v %.6f %.6f %.6f')
    np.savetxt(f, UV, fmt='vt %.6f %.6f')
    F = np.empty((len(I), 6), dtype=np.int64)
    F[:,0::2] = I + 1; F[:,1::2] = np.arange(len(I)*3).reshape(-1,3) + 1
    np.savetxt(f, F, fmt='f %d/%d %d/%d %d/%d')
ms.load_new_mesh(out_obj + '.in.obj')
print('loaded', ms.current_mesh().face_number())
ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=target, qualitythr=0.5, extratcoordw=1.0, preserveboundary=True, optimalplacement=True, preservenormal=True, planarquadric=True)
print('after', ms.current_mesh().face_number(), ms.current_mesh().vertex_number())
ms.save_current_mesh(out_obj, save_wedge_texcoord=True, save_vertex_normal=False, save_textures=False)
