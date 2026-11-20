import sys, os, time
sys.path.insert(0, os.path.expanduser('~/Library/Caches/drift-hy3d/Hunyuan3D-2'))
import torch
from PIL import Image
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained('tencent/Hunyuan3D-2mini', subfolder='hunyuan3d-dit-v2-mini-turbo',
                                                        use_safetensors=True, device='mps', dtype=torch.float16)
try: pipe.enable_flashvdm()
except Exception as e: print('no flashvdm', e)
for img, out in zip(sys.argv[1::2], sys.argv[2::2]):
    t = time.time()
    mesh = pipe(image=Image.open(img).convert('RGBA'), num_inference_steps=5, octree_resolution=256,
                num_chunks=20000, generator=torch.manual_seed(1234), output_type='trimesh')[0]
    mesh.export(out); print('saved', out, len(mesh.faces), round(time.time() - t), 's', flush=True)
