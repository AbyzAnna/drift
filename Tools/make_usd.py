# Turns slim.obj + textures/ (color.jpg, roughness.jpg, normal.png) into a USD file for usdzip.
#   python Tools/make_usd.py slim.obj Pip3D.usdc && usdzip Pip3D.usdz Pip3D.usdc textures/*
import sys, numpy as np
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt
obj, out = sys.argv[1], sys.argv[2]
V=[];T=[];F=[]
for line in open(obj):
    if line.startswith('v '): V.append(list(map(float,line.split()[1:4])))
    elif line.startswith('vt '): T.append(list(map(float,line.split()[1:3])))
    elif line.startswith('f '):
        F.append([tuple(int(x)-1 for x in w.split('/')[:2]) for w in line.split()[1:]])
V=np.array(V); T=np.array(T)
vi=np.array([[a for a,_ in f] for f in F]); ti=np.array([[b for _,b in f] for f in F])
# smooth normals
fn=np.cross(V[vi[:,1]]-V[vi[:,0]], V[vi[:,2]]-V[vi[:,0]])
N=np.zeros_like(V)
for k in range(3): np.add.at(N, vi[:,k], fn)
N/=np.linalg.norm(N,axis=1,keepdims=True)+1e-12
st=Usd.Stage.CreateNew(out)
UsdGeom.SetStageUpAxis(st, UsdGeom.Tokens.y); UsdGeom.SetStageMetersPerUnit(st, 0.2)
root=UsdGeom.Xform.Define(st,'/Penguin'); st.SetDefaultPrim(root.GetPrim())
m=UsdGeom.Mesh.Define(st,'/Penguin/Body')
m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(V.astype(np.float32)))
m.CreateFaceVertexCountsAttr(Vt.IntArray([3]*len(vi)))
m.CreateFaceVertexIndicesAttr(Vt.IntArray(vi.flatten().tolist()))
m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(N.astype(np.float32))); m.SetNormalsInterpolation('vertex')
m.CreateSubdivisionSchemeAttr('none')
lo,hi=V.min(0),V.max(0); m.CreateExtentAttr([Gf.Vec3f(*lo),Gf.Vec3f(*hi)])
pv=UsdGeom.PrimvarsAPI(m).CreatePrimvar('st',Sdf.ValueTypeNames.TexCoord2fArray,UsdGeom.Tokens.faceVarying)
pv.Set(Vt.Vec2fArray.FromNumpy(T.astype(np.float32))); pv.SetIndices(Vt.IntArray(ti.flatten().tolist()))
mat=UsdShade.Material.Define(st,'/Penguin/Materials/Plush')
sh=UsdShade.Shader.Define(st,'/Penguin/Materials/Plush/Surface'); sh.CreateIdAttr('UsdPreviewSurface')
mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(),'surface')
rd=UsdShade.Shader.Define(st,'/Penguin/Materials/Plush/uv'); rd.CreateIdAttr('UsdPrimvarReader_float2')
rd.CreateInput('varname',Sdf.ValueTypeNames.String).Set('st')
def tex(name,file,cs):
    t=UsdShade.Shader.Define(st,'/Penguin/Materials/Plush/'+name); t.CreateIdAttr('UsdUVTexture')
    t.CreateInput('file',Sdf.ValueTypeNames.Asset).Set(file)
    t.CreateInput('sourceColorSpace',Sdf.ValueTypeNames.Token).Set(cs)
    t.CreateInput('st',Sdf.ValueTypeNames.Float2).ConnectToSource(rd.ConnectableAPI(),'result')
    return t
c=tex('color','textures/color.jpg','sRGB'); sh.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).ConnectToSource(c.ConnectableAPI(),'rgb')
c.CreateOutput('rgb',Sdf.ValueTypeNames.Float3)
r=tex('rough','textures/roughness.jpg','raw'); r.CreateOutput('r',Sdf.ValueTypeNames.Float)
sh.CreateInput('roughness',Sdf.ValueTypeNames.Float).ConnectToSource(r.ConnectableAPI(),'r')
n=tex('normal','textures/normal.png','raw'); n.CreateOutput('rgb',Sdf.ValueTypeNames.Float3)
n.CreateInput('scale',Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2,2,2,1)); n.CreateInput('bias',Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1,-1,-1,0))
sh.CreateInput('normal',Sdf.ValueTypeNames.Normal3f).ConnectToSource(n.ConnectableAPI(),'rgb')
sh.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(0.0)
UsdGeom.Imageable(m).GetPrim().ApplyAPI(UsdShade.MaterialBindingAPI)
UsdShade.MaterialBindingAPI(m).Bind(mat)
st.GetRootLayer().Save()
print('faces',len(vi),'bbox',lo,hi)
