# Paints a shape-only mesh with its reference picture: front-visible vertices take the picture,
# hidden ones take a "body colour" version (large median filter, so eyes/nose don't repeat on the back).
# Writes slim.obj (decimated, UVs) + textures/color.jpg for make_usd.py.
import sys, numpy as np, trimesh, pymeshlab
from PIL import Image, ImageFilter
mesh_p, img_p, outdir, target = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
m = trimesh.load(mesh_p, force='mesh')
# decimate first (no UVs yet)
m.export(outdir + '.in.obj')
ms = pymeshlab.MeshSet(); ms.load_new_mesh(outdir + '.in.obj')
ms.meshing_decimation_quadric_edge_collapse(targetfacenum=target)
cm = ms.current_mesh(); V = cm.vertex_matrix(); F = cm.face_matrix()
im = Image.open(img_p).convert('RGBA'); A = np.asarray(im)
ys, xs = np.nonzero(A[:, :, 3] > 128); x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
mx0, my0 = V[:, 0].min(), V[:, 1].min(); mx1, my1 = V[:, 0].max(), V[:, 1].max()
u = x0 + (V[:, 0] - mx0) / (mx1 - mx0) * (x1 - x0)
v = y1 - (V[:, 1] - my0) / (my1 - my0) * (y1 - y0)
W, H = im.size
# visibility from the front (+Z) with a z-buffer at image resolution / 2
R = 2; zb = np.full((H // R + 1, W // R + 1), -np.inf)
tri = trimesh.Trimesh(V, F, process=False)
pts, fid = trimesh.sample.sample_surface(tri, 600000)
pu = (x0 + (pts[:, 0] - mx0) / (mx1 - mx0) * (x1 - x0)) / R
pv = (y1 - (pts[:, 1] - my0) / (my1 - my0) * (y1 - y0)) / R
pi_, pj = np.clip(pv.astype(int), 0, zb.shape[0]-1), np.clip(pu.astype(int), 0, zb.shape[1]-1)
np.maximum.at(zb, (pi_, pj), pts[:, 2])
vi, vj = np.clip((v / R).astype(int), 0, zb.shape[0]-1), np.clip((u / R).astype(int), 0, zb.shape[1]-1)
depth = V[:, 2].max() - V[:, 2].min()
vis = V[:, 2] >= zb[vi, vj] - depth * 0.03
# smooth the visibility a bit over the mesh so seams fall on grazing angles
N = tri.vertex_normals; vis &= N[:, 2] > 0.15
# texture: left half picture, right half body colour
rgb = Image.alpha_composite(Image.new('RGBA', im.size, (235, 230, 222, 255)), im).convert('RGB')
small = rgb.resize((W // 4, H // 4)); body = small.filter(ImageFilter.MedianFilter(15)).filter(ImageFilter.GaussianBlur(3)).resize((W, H))
# outside the silhouette, extend colours inward-out so edge texels aren't background
tex = Image.new('RGB', (W * 2, H)); tex.paste(rgb, (0, 0)); tex.paste(body, (W, 0))
U = np.where(vis, u, u + W) / (2 * W); Vv = 1 - v / H
FV = np.stack([U, Vv], 1)
# a face whose corners disagree gets all corners from the hidden half (avoid stretched seams)
fvis = vis[F]; mixed = fvis.any(1) & ~fvis.all(1)
UVw = FV[F].copy()
for k in range(3):
    sel = mixed & fvis[:, k]
    UVw[sel, k, 0] += 0.5
import os; os.makedirs(outdir + '/textures', exist_ok=True)
tex.resize((2048, 1024), Image.LANCZOS).save(outdir + '/textures/color.jpg', quality=90)
with open(outdir + '/slim.obj', 'w') as f:
    np.savetxt(f, V, fmt='v %.6f %.6f %.6f')
    np.savetxt(f, UVw.reshape(-1, 2), fmt='vt %.6f %.6f')
    idx = np.empty((len(F), 6), int); idx[:, 0::2] = F + 1; idx[:, 1::2] = np.arange(len(F) * 3).reshape(-1, 3) + 1
    np.savetxt(f, idx, fmt='f %d/%d %d/%d %d/%d')
print('faces', len(F), 'visible', vis.mean())
