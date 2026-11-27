"""Original flat-ink body animation, derived from Rush's existing cook portraits.
Run from repo root; frame cells 128x176, two frames each for idle/walk/work/serve/rest.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/art'
INK = '#211b22'


def portrait(name):
    im = Image.open(ART / f'cook_{name}.png').convert('RGBA')
    # The approved portrait art is keyed to navy. Keep the face/hair and remove the key.
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = im.getpixel((x, y))
            if b > r + 8 and b > g + 5 and r < 80 and g < 85:
                im.putpixel((x, y), (0, 0, 0, 0))
    return im.crop((24, 0, 124, 128)).resize((64, 82), Image.Resampling.LANCZOS)


def draw_frame(name, state, phase):
    im = Image.new('RGBA', (128, 176))
    d = ImageDraw.Draw(im)
    apron, skin = {'dev': ('#596d77', '#e9a266'), 'mo': ('#a33b3a', '#d98958'), 'jo': ('#cc9c40', '#9e6043')}[name]
    def poly(points, color):
        d.polygon(points, fill=color, outline=INK, width=3)
    def limb(points, color, width):
        d.line(points, fill=INK, width=width+6, joint='curve')
        d.line(points, fill=color, width=width, joint='curve')
    bob = (phase if state in ('idle', 'rest') else -phase*3)
    stride = (12 if phase else -12) if state == 'walk' else 0
    # sturdy non-slip shoes and dark work trousers
    for x, step in ((52,stride),(76,-stride)):
        limb([(x,119),(x+step//2,140),(x+step,159)], '#34383e', 17)
        d.rounded_rectangle((x+step-11,151,x+step+13,168),5,fill='#27252a',outline=INK,width=3)
    # chef coat, apron, collar, buttons and waist tie
    poly([(42,71+bob),(85,71+bob),(94,92),(86,126),(42,126),(34,92)], '#eee6d8')
    poly([(48,80),(80,80),(86,129),(43,129)], apron)
    d.line((48,114,81,114),fill=INK,width=3)
    d.rectangle((54,101,74,113),outline=INK,width=2)
    d.line((56,72,64,83,72,72),fill=INK,width=3)
    # arms: mirrored stride, stirring, carrying a dish, or resting low
    if state == 'work':
        arms = [[(40,85),(27,99),(52+phase*8,94)],[(86,85),(99,99),(74-phase*7,94)]]
    elif state == 'serve':
        arms = [[(40,85),(30,95),(57,83)],[(86,85),(98,95),(74,83)]]
    else:
        arms = [[(40,85),(30+stride//2,106),(35+stride,121)],[(86,85),(98-stride//2,106),(93-stride,121)]]
    for arm in arms:
        limb(arm[:2], '#eee6d8', 13)
        limb(arm[1:], skin, 10)
    if state == 'work':
        d.line((57+phase*8,94,75+phase*8,76),fill=INK,width=5)
        d.ellipse((70+phase*8,70,80+phase*8,81),fill='#aeb9bd',outline=INK,width=2)
    elif state == 'serve':
        d.ellipse((38,73-phase*2,91,87-phase*2),fill='#eee6d8',outline=INK,width=3)
        d.ellipse((49,69-phase*2,80,80-phase*2),fill='#c07c38',outline=INK,width=2)
    if name != 'jo':
        im.alpha_composite(portrait(name),(32,-2+bob))
    else:
        # Jo had no portrait in the current game; original temp cook with a cap and round glasses.
        d.ellipse((36,15+bob,92,76+bob),fill=skin,outline=INK,width=3)
        d.rounded_rectangle((33,8+bob,95,34+bob),12,fill='#d7aa49',outline=INK,width=3)
        d.polygon([(36,30+bob),(95,30+bob),(103,38+bob),(34,38+bob)],fill='#e0bc62',outline=INK,width=3)
        for x in [49,76]:
            d.ellipse((x-10,40+bob,x+10,56+bob),outline=INK,width=3)
            d.ellipse((x-2,45+bob,x+3,50+bob),fill=INK)
        d.line((59,48+bob,66,48+bob),fill=INK,width=3)
        d.arc((55,53+bob,77,68+bob),0,180,fill=INK,width=3)
    return im


for name in ('dev','mo','jo'):
    sheet = Image.new('RGBA',(128*2,176*5))
    for row,state in enumerate(('idle','walk','work','serve','rest')):
        for phase in range(2):
            sheet.alpha_composite(draw_frame(name,state,phase),(128*phase,176*row))
    sheet.save(ART / 'crew' / f'{name}.png')
