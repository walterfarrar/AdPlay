from pathlib import Path

from PIL import Image

src = Path(r"C:\Users\walte\.cursor\projects\c-git-AdPlay\assets")
files = [
    ("stage-01-garage.png", "StageLevel1", "stage_level_1"),
    ("stage-02-workbench.png", "StageLevel2", "stage_level_2"),
    ("stage-03-small-farm.png", "StageLevel3", "stage_level_3"),
    ("stage-04-mining-farm.png", "StageLevel4", "stage_level_4"),
    ("stage-05-warehouse.png", "StageLevel5", "stage_level_5"),
    ("stage-06-industrial.png", "StageLevel6", "stage_level_6"),
    ("stage-07-data-hall.png", "StageLevel7", "stage_level_7"),
    ("stage-08-mega-farm.png", "StageLevel8", "stage_level_8"),
    ("stage-09-campus.png", "StageLevel9", "stage_level_9"),
    ("stage-10-foundry.png", "StageLevel10", "stage_level_10"),
]

ios_root = Path(r"C:\git\AdPlay\ios\AdPlay\Assets.xcassets")
and_root = Path(r"C:\git\AdPlay\android\app\src\main\res\drawable-nodpi")
web_root = Path(r"C:\git\AdPlay\web\images")
and_root.mkdir(parents=True, exist_ok=True)
web_root.mkdir(parents=True, exist_ok=True)

contents = """{
  "images" : [
    {
      "filename" : "stage.jpg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

for src_name, ios_set, android_name in files:
    im = Image.open(src / src_name).convert("RGB")
    im.thumbnail((1080, 1920), Image.Resampling.LANCZOS)
    ios_dir = ios_root / f"{ios_set}.imageset"
    ios_dir.mkdir(parents=True, exist_ok=True)
    ios_jpg = ios_dir / "stage.jpg"
    and_jpg = and_root / f"{android_name}.jpg"
    web_jpg = web_root / src_name.replace(".png", ".jpg")
    for dest in (ios_jpg, and_jpg, web_jpg):
        im.save(dest, "JPEG", quality=82, optimize=True, progressive=True)
    (ios_dir / "Contents.json").write_text(contents, encoding="utf-8")
    print(f"{src_name} -> {im.size} {ios_jpg.stat().st_size // 1024}KB")
