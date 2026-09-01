from pathlib import Path

from PIL import Image

src = Path(r"C:\Users\walte\.cursor\projects\c-git-AdPlay\assets")
files = [
    ("wheel-face-01-garage.png", "WheelFace1", "wheel_face_1", "wheel-face-01-garage.jpg"),
    ("wheel-face-02-workbench.png", "WheelFace2", "wheel_face_2", "wheel-face-02-workbench.jpg"),
    ("wheel-face-03-small-farm.png", "WheelFace3", "wheel_face_3", "wheel-face-03-small-farm.jpg"),
    ("wheel-face-04-mining-farm.png", "WheelFace4", "wheel_face_4", "wheel-face-04-mining-farm.jpg"),
    ("wheel-face-05-warehouse.png", "WheelFace5", "wheel_face_5", "wheel-face-05-warehouse.jpg"),
    ("wheel-face-06-industrial.png", "WheelFace6", "wheel_face_6", "wheel-face-06-industrial.jpg"),
    ("wheel-face-07-data-hall.png", "WheelFace7", "wheel_face_7", "wheel-face-07-data-hall.jpg"),
    ("wheel-face-08-mega-farm.png", "WheelFace8", "wheel_face_8", "wheel-face-08-mega-farm.jpg"),
    ("wheel-face-09-campus.png", "WheelFace9", "wheel_face_9", "wheel-face-09-campus.jpg"),
    ("wheel-face-10-foundry.png", "WheelFace10", "wheel_face_10", "wheel-face-10-foundry.jpg"),
]

ios_root = Path(r"C:\git\AdPlay\ios\AdPlay\Assets.xcassets")
and_root = Path(r"C:\git\AdPlay\android\app\src\main\res\drawable-nodpi")
web_root = Path(r"C:\git\AdPlay\web\images")
and_root.mkdir(parents=True, exist_ok=True)
web_root.mkdir(parents=True, exist_ok=True)

contents = """{
  "images" : [
    {
      "filename" : "face.jpg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

for src_name, ios_set, android_name, web_name in files:
    im = Image.open(src / src_name).convert("RGB")
    im.thumbnail((768, 768), Image.Resampling.LANCZOS)
    ios_dir = ios_root / f"{ios_set}.imageset"
    ios_dir.mkdir(parents=True, exist_ok=True)
    dests = (
        ios_dir / "face.jpg",
        and_root / f"{android_name}.jpg",
        web_root / web_name,
    )
    for dest in dests:
        im.save(dest, "JPEG", quality=84, optimize=True, progressive=True)
    (ios_dir / "Contents.json").write_text(contents, encoding="utf-8")
    print(f"{src_name} -> {im.size} {(ios_dir / 'face.jpg').stat().st_size // 1024}KB")
