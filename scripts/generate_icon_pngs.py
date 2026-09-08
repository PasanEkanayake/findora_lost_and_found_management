from PIL import Image, ImageDraw

TEAL = (15, 110, 86, 255)      # #0F6E56
WHITE = (255, 255, 255, 255)
AMBER = (232, 163, 61, 255)    # #E8A33D
SIZE = 1024

def draw_pin(draw, cx, cy, head_r, tip_dy, dot_r):
    """Head = circle, tail = triangle tapering to a point — a simplified,
    crisp re-draw of the same pin silhouette used in app_icon.svg."""
    draw.ellipse(
        [cx - head_r, cy - head_r, cx + head_r, cy + head_r],
        fill=WHITE,
    )
    draw.polygon(
        [
            (cx - head_r * 0.7, cy),
            (cx + head_r * 0.7, cy),
            (cx, cy + tip_dy),
        ],
        fill=WHITE,
    )
    draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=AMBER)


def make_app_icon(path):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(SIZE * 0.22)
    draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=TEAL)
    draw_pin(draw, cx=SIZE // 2, cy=SIZE * 0.505, head_r=SIZE * 0.215,
             tip_dy=SIZE * 0.275, dot_r=SIZE * 0.093)
    img.save(path)


def make_adaptive_foreground(path):
    # Adaptive icons only guarantee the inner ~66% survives masking, so the
    # pin is smaller and more centered here than in the flat app icon.
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_pin(draw, cx=SIZE // 2, cy=SIZE * 0.50, head_r=SIZE * 0.15,
              tip_dy=SIZE * 0.19, dot_r=SIZE * 0.065)
    img.save(path)


if __name__ == "__main__":
    make_app_icon("/home/claude/findora/assets/images/app_icon.png")
    make_adaptive_foreground("/home/claude/findora/assets/images/app_icon_foreground.png")
    print("done")
