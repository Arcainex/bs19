// BeyondSurvival - faction emblems. Layered SVG from a small JSON spec, shared as nui://bs_ui/html/shared/emblem.js.
// The ids below are mirrored in bs_factions/shared/sh_emblem.lua (the server only stores ids it knows). Keep both in step.
(function (global) {
    'use strict';
    if (global.BSEmblem) return;

    const HEX = /^#[0-9a-f]{6}$/i;
    let uidN = 0;

    // helpers, symbols live in a 100x100 box
    const P = (d, extra) => `<path d="${d}"${extra ? ' ' + extra : ''}/>`;
    const C = (cx, cy, r, extra) => `<circle cx="${cx}" cy="${cy}" r="${r}"${extra ? ' ' + extra : ''}/>`;
    const R = (x, y, w, h, rx, extra) => `<rect x="${x}" y="${y}" width="${w}" height="${h}"${rx ? ` rx="${rx}"` : ''}${extra ? ' ' + extra : ''}/>`;
    const G = (t, inner) => `<g transform="${t}">${inner}</g>`;
    const LINE = (d, w) => `<path d="${d}" fill="none" stroke="#000" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
    const STROKE = (d, w, cap) => `<path d="${d}" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="${cap || 'round'}" stroke-linejoin="round"/>`;
    const f = (n) => Math.round(n * 100) / 100;
    const pt = (cx, cy, r, deg) => { const a = deg * Math.PI / 180; return [f(cx + r * Math.cos(a)), f(cy + r * Math.sin(a))]; };

    function star(cx, cy, ro, ri, n, rot) {
        let d = '';
        for (let i = 0; i < n * 2; i++) {
            const [x, y] = pt(cx, cy, i % 2 ? ri : ro, (rot || -90) + i * 180 / n);
            d += (i ? 'L' : 'M') + x + ' ' + y;
        }
        return d + 'Z';
    }
    function poly(cx, cy, r, n, rot) {
        let d = '';
        for (let i = 0; i < n; i++) { const [x, y] = pt(cx, cy, r, (rot || 0) + i * 360 / n); d += (i ? 'L' : 'M') + x + ' ' + y; }
        return d + 'Z';
    }
    function gear(cx, cy, ro, ri, n) {
        let d = '';
        const step = 360 / n;
        for (let i = 0; i < n; i++) {
            const a = i * step - 90;
            const pts = [pt(cx, cy, ri, a - step * 0.5), pt(cx, cy, ri, a - step * 0.24), pt(cx, cy, ro, a - step * 0.16), pt(cx, cy, ro, a + step * 0.16), pt(cx, cy, ri, a + step * 0.24)];
            pts.forEach((p, k) => { d += (i === 0 && k === 0 ? 'M' : 'L') + p[0] + ' ' + p[1]; });
        }
        return d + 'Z';
    }
    function sector(cx, cy, r1, r2, a1, a2) {
        const [x1, y1] = pt(cx, cy, r1, a1), [x2, y2] = pt(cx, cy, r2, a1), [x3, y3] = pt(cx, cy, r2, a2), [x4, y4] = pt(cx, cy, r1, a2);
        return `M${x1} ${y1}L${x2} ${y2}A${r2} ${r2} 0 0 1 ${x3} ${y3}L${x4} ${y4}A${r1} ${r1} 0 0 0 ${x1} ${y1}Z`;
    }
    const mirror = (inner) => inner + G('translate(100 0) scale(-1 1)', inner);

    // pieces reused by several symbols
    const SKULL = 'M50 12C29 12 17 27 17 46c0 11 5 18 12 22v10c0 3 2 5 5 5h32c3 0 5-2 5-5V68c7-4 12-11 12-22 0-19-12-34-33-34Z';
    const SKULL_CUT = C(37, 47, 8.5) + C(63, 47, 8.5) + P('M50 56l-5 9h10Z') + R(39.5, 72, 3, 9) + R(48.5, 72, 3, 9) + R(57.5, 72, 3, 9);
    const RIFLE = 'M-48-3l18-5v14l-18 4ZM-31-8h42v11h-42ZM10-6h19v7H10ZM28-3.5h20V-1H28ZM41-8h2.5v5H41ZM-6 3h10q4 9 10 15l-8 3q-7-7-12-18ZM-21 3h8l-3 11h-8Z';
    const WING = 'M47 40C38 32 22 26 6 26c5 4 8 6 9 9-5-1-9-1-12 0 5 3 8 6 9 9-4 0-7 1-9 3 5 2 9 4 11 8-3 1-5 2-6 4 6 1 12 3 17 7 5 4 10 6 17 6l5-10Z';
    const WING_CUT = LINE('M14 36q14 2 30 10M12 46q14 2 31 8M16 57q12 1 27 4', 2.2);

    // Each symbol: list of layers [body, cut]. Body is filled with the symbol colour, cut is punched out of that layer.
    const SYMBOLS = {
        skull: () => [[P(SKULL), SKULL_CUT]],
        skull_bones: () => [
            [G('rotate(40 50 50)', R(12, 45, 76, 9, 4.5) + C(12, 46, 6) + C(12, 54, 6) + C(88, 46, 6) + C(88, 54, 6)) + G('rotate(-40 50 50)', R(12, 45, 76, 9, 4.5) + C(12, 46, 6) + C(12, 54, 6) + C(88, 46, 6) + C(88, 54, 6)),
                G('translate(20 14) scale(.6)', `<path d="${SKULL}" fill="#000" stroke="#000" stroke-width="12"/>`)],
            [G('translate(20 14) scale(.6)', P(SKULL)), G('translate(20 14) scale(.6)', SKULL_CUT)],
        ],
        ram_skull: () => [
            [P('M28 30C12 22 4 36 8 50c3 10 12 14 20 10-6-2-10-7-9-13 1-7 8-9 13-5ZM72 30c16-8 24 6 20 20-3 10-12 14-20 10 6-2 10-7 9-13-1-7-8-9-13-5Z'), ''],
            [P('M50 20c-14 0-22 10-22 24 0 9 4 15 9 19v12c0 3 3 6 6 6h14c3 0 6-3 6-6V63c5-4 9-10 9-19 0-14-8-24-22-24Z'), C(40, 45, 6.5) + C(60, 45, 6.5) + P('M50 54l-4 8h8Z') + R(44, 70, 2.5, 8) + R(53.5, 70, 2.5, 8)],
        ],
        wolf: () => [[P('M50 90 37 76l-12-5-6-19 2-22-4-21 19 14 14-4 14 4 19-14-4 21 2 22-6 19-12 5Z'),
            P('M23 18l10 9-7 6ZM77 18l-10 9 7 6ZM31 44l13 3-3 4ZM69 44l-13 3 3 4ZM44 70h12l-6 7Z') + LINE('M41 56l9 8 9-8', 2.4) + LINE('M50 30v20', 2)]],
        crow: () => [[P('M12 37l18-6c3-8 15-11 23-5 10 7 17 18 20 29l21 24H84l5 8-17-12c-9 5-19 4-26-2-8-7-12-18-13-28-3-3-9-6-21-8Z') + STROKE('M48 75l-3 14M57 77l1 12M41 90h9M53 90h9', 3),
            C(40, 32, 2.4) + LINE('M40 49q15 4 27 19M45 58q11 5 19 15', 2)]],
        snake: () => [[STROKE('M28 86c-18-8-16-30 6-31 18-1 38 2 40-16 1-14-14-20-26-14', 10) + P('M44 21c4-9 16-11 22-5 4 4 2 12-6 12-6 1-13-2-16-7Z') + STROKE('M66 18l9-3m-9 3 8 4', 1.6),
            C(57, 19, 2.2) + LINE('M24 70q8 4 16 0M54 50q8-4 14 2', 1.6)]],
        wings: () => [[mirror(P(WING)) + C(50, 50, 13), mirror(WING_CUT) + C(50, 50, 7)]],
        winged_wheel: () => [
            [mirror(P(WING)), mirror(WING_CUT) + C(50, 50, 22)],
            [C(50, 50, 19), C(50, 50, 12.5)],
            [C(50, 50, 4) + STROKE('M50 39v22M39 50h22M42 42l16 16M58 42 42 58', 2.6), ''],
        ],
        eagle: () => [[mirror(P('M48 30C40 22 24 16 4 18c6 4 9 7 10 10-5 0-8 1-10 3 6 2 10 4 11 7-3 1-6 2-7 4 7 1 13 4 17 8-2 1-4 3-5 5 8 0 15 3 20 8l6-6Z')) + P('M50 18c-6 0-10 5-10 11 0 4 2 7 4 9l-2 26 8 14 8-14-2-26c2-2 4-5 4-9 0-6-4-11-10-11Z') + P('M58 24l8 3-7 3Z'),
            C(53, 25, 1.8) + mirror(LINE('M16 30q12 2 26 10M14 40q12 2 27 8', 1.8)) + LINE('M46 50h8M46 58h8', 1.8)]],
        star: () => [[P(star(50, 52, 42, 17, 5)), '']],
        star_ring: () => [[C(50, 50, 44), C(50, 50, 38)], [P(star(50, 52, 34, 13.5, 5)), '']],
        compass: () => [[P(star(50, 50, 44, 9, 4)) + P(star(50, 50, 28, 7, 4, -45)), C(50, 50, 4)]],
        chevrons: () => [[P('M10 30 50 10l40 20v12L50 22 10 42ZM10 52l40-20 40 20v12L50 44 10 64ZM10 74l40-20 40 20v12L50 66 10 86Z'), '']],
        crossed_rifles: () => [
            [G('translate(50 48) rotate(-42)', P(RIFLE)), G('translate(50 48) rotate(42) scale(-1 1)', `<path d="${RIFLE}" fill="#000" stroke="#000" stroke-width="6"/>`)],
            [G('translate(50 48) rotate(42) scale(-1 1)', P(RIFLE)), ''],
        ],
        crosshair: () => [[C(50, 50, 38), C(50, 50, 31)], [R(47, 2, 6, 32) + R(47, 66, 6, 32) + R(2, 47, 32, 6) + R(66, 47, 32, 6) + C(50, 50, 4.5), '']],
        bullets: () => [[[22, 50, 78].map((x) => P(`M${x - 8} 88V44c0-14 4-24 8-30 4 6 8 16 8 30v44Z`)).join(''), LINE('M14 74h72', 2.6) + LINE('M14 80h72', 1.4)]],
        dagger: () => [[P('M50 4l7 12v48H43V16Z') + R(28, 62, 44, 7, 2) + R(45.5, 69, 9, 16) + C(50, 90, 6), LINE('M50 14v48', 1.6) + LINE('M45.5 74h9M45.5 79h9', 1.6)]],
        axes: () => {
            const axe = 'M-3-42h6v84h-6ZM2-40c10-2 22 2 26 12 2 6 2 12 0 18-8-6-18-8-26-6Z';
            return [[G('translate(50 52) rotate(-34)', P(axe)), G('translate(50 52) rotate(34) scale(-1 1)', `<path d="${axe}" fill="#000" stroke="#000" stroke-width="5"/>`)],
                [G('translate(50 52) rotate(34) scale(-1 1)', P(axe)), '']];
        },
        hammer: () => [[G('rotate(-35 50 50)', R(46, 26, 8, 70, 2) + P('M24 8h52c4 0 6 3 6 6v10c0 3-2 6-6 6H24c-4 0-6-3-6-6V14c0-3 2-6 6-6Z')), G('rotate(-35 50 50)', LINE('M46 20h8', 2.2) + LINE('M46 82h8M46 88h8', 1.6))]],
        wrenches: () => {
            const w = 'M-4-30h8v58h-8ZM0-48a13 13 0 1 1-.1 0ZM0 26a10 10 0 1 1-.1 0Z';
            const cut = R(-4.5, -54, 9, 13) + R(-3.5, 33, 7, 10);
            return [[G('translate(50 52) rotate(-42)', P(w)), G('translate(50 52) rotate(-42)', cut) + G('translate(50 52) rotate(42)', `<path d="${w}" fill="#000" stroke="#000" stroke-width="5"/>`)],
                [G('translate(50 52) rotate(42)', P(w)), G('translate(50 52) rotate(42)', cut)]];
        },
        gear: () => [[P(gear(50, 50, 46, 36, 10)), C(50, 50, 14)]],
        pistons: () => {
            const p = 'M-9-44h18v24H-9ZM-3.5-20h7v52h-7ZM-8 30h16v12H-8Z';
            const cut = LINE('M-9-36h18M-9-28h18', 2);
            return [[G('translate(50 50) rotate(-40)', P(p)), G('translate(50 50) rotate(-40)', cut) + G('translate(50 50) rotate(40)', `<path d="${p}" fill="#000" stroke="#000" stroke-width="5"/>`)],
                [G('translate(50 50) rotate(40)', P(p)), G('translate(50 50) rotate(40)', cut)]];
        },
        wheel: () => [[C(50, 50, 44), C(50, 50, 30) + [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330].map((a) => { const [x1, y1] = pt(50, 50, 39, a), [x2, y2] = pt(50, 50, 46, a); return LINE(`M${x1} ${y1}L${x2} ${y2}`, 3); }).join('')],
            [C(50, 50, 9) + STROKE('M50 22v56M22 50h56M30 30l40 40M70 30 30 70', 4), C(50, 50, 4)]],
        flame: () => [[P('M50 92c-20 0-30-14-28-30 2-14 12-20 12-34 8 6 10 14 10 20 4-8 8-18 6-36 14 12 24 28 22 46 4-4 6-8 6-12 6 10 4 26-2 34-6 8-16 12-26 12Z'),
            P('M50 86c-8 0-13-7-11-15 2-7 8-10 9-17 5 6 8 11 7 17 3-2 5-4 6-7 3 7 1 17-11 22Z')]],
        bolt: () => [[P('M60 4 22 54h24L36 96l42-56H54L66 4Z'), '']],
        biohazard: () => {
            const lobes = [-90, 30, 150].map((a) => { const [x, y] = pt(50, 54, 17, a); return C(x, y, 21); }).join('');
            const holes = [-90, 30, 150].map((a) => { const [x, y] = pt(50, 54, 24, a); return C(x, y, 15); }).join('');
            const gaps = [90, 210, 330].map((a) => { const [x, y] = pt(50, 54, 30, a); return LINE(`M50 54L${x} ${y}`, 3.2); }).join('');
            return [[lobes, holes + C(50, 54, 6.5) + gaps], [`<circle cx="50" cy="54" r="15.5" fill="none" stroke="currentColor" stroke-width="5"/>`, gaps + [-90, 30, 150].map((a) => { const [x, y] = pt(50, 54, 24, a); return C(x, y, 9.5); }).join('')]];
        },
        radiation: () => [[C(50, 50, 7) + [-90, 30, 150].map((a) => P(sector(50, 50, 12, 40, a - 30, a + 30))).join(''), ''], [`<circle cx="50" cy="50" r="46" fill="none" stroke="currentColor" stroke-width="4"/>`, '']],
        fist: () => [[P('M30 22c0-3 2-5 5-5s5 2 5 5v-2c0-3 2-5 5-5s5 2 5 5v1c0-3 2-5 5-5s5 2 5 5v3c0-3 2-5 5-5s5 2 5 5v26c0 12-6 20-12 24v14H38V76c-6-4-10-10-10-18V40c0-2 1-3 2-4Z'),
            LINE('M40 18v20M50 18v20M60 21v18', 2.4) + LINE('M30 44h24c3 0 4 3 2 5l-6 6', 2.4) + LINE('M38 86h24', 2)]],
        hand: () => [[P('M36 90V60L20 44c-3-3-2-7 1-8 3-2 6-1 8 1l7 7V18c0-3 2-5 5-5s5 2 5 5v22-28c0-3 2-5 5-5s5 2 5 5v28-24c0-3 2-5 5-5s5 2 5 5v26-16c0-3 2-5 5-5s5 2 5 5v34c0 12-6 20-12 24v10Z'), LINE('M46 40V22M56 40V16M66 42V24', 2)]],
        crown: () => [[P('M14 30l18 20 18-30 18 30 18-20-4 44H18Z') + R(18, 78, 64, 10, 1) + C(14, 28, 5) + C(50, 18, 5) + C(86, 28, 5), C(32, 62, 4) + C(50, 58, 5) + C(68, 62, 4)]],
        eye: () => [[P('M6 50c12-20 26-30 44-30s32 10 44 30c-12 20-26 30-44 30S18 70 6 50Z'), C(50, 50, 20)], [C(50, 50, 11), C(46, 46, 3)]],
        anchor: () => [[C(50, 16, 8) + R(46, 22, 8, 64) + R(30, 30, 40, 7, 2) + STROKE('M16 58c2 18 16 28 34 28s32-10 34-28', 7) + P('M8 62l8-12 8 12ZM76 62l8-12 8 12Z'), C(50, 16, 3.5)]],
        sprout: () => [[P('M47 88V54c-2-10-10-18-24-20-6-1-12 0-14 1 0 16 10 26 24 28 6 1 10 0 14-1v-6c-6 0-12-3-16-8 6 3 12 5 16 6V46c0-14 10-26 28-30 6-1 10 0 12 1 0 18-10 30-26 32-4 1-7 0-8 0v6c6-2 12-6 16-12-2 8-8 14-16 16v29Z') + P('M18 92c8-6 20-8 32-8s24 2 32 8Z'), '']],
        tree: () => [[P('M50 6 26 40h12L20 62h14L14 84h72L66 62h14L62 40h12Z') + R(45, 84, 10, 12), '']],
        house: () => [[P('M50 10 8 46h10v42h64V46h10L74 30V14h-9v8Z'), R(42, 62, 16, 26) + R(26, 52, 11, 11) + R(63, 52, 11, 11)]],
        tower: () => [[P('M30 92l6-56h-6V22h40v14h-6l6 56Z') + P('M24 22 50 6l26 16Z'), R(42, 28, 16, 8) + LINE('M38 44l24 20M62 44 38 64M36 66l28 22M64 66 36 88', 2.2)]],
        mountain: () => [[P('M4 86 36 30l14 22 14-26 32 60Z'), P('M36 30l8 14-8-4-6 6ZM64 26l9 16-9-5-6 7Z')]],
        medical: () => [[P('M38 10h24v28h28v24H62v28H38V62H10V38h28Z'), '']],
        heart: () => [[P('M50 88 12 52C2 42 2 24 14 16c10-6 24-4 36 10 12-14 26-16 36-10 12 8 12 26 2 36Z'), LINE('M18 50h18l6-12 10 26 8-18 6 6h16', 3)]],
        key: () => [[C(28, 50, 20) + R(44, 45, 50, 10) + R(76, 55, 7, 13) + R(88, 55, 6, 10), C(28, 50, 9)]],
        warning: () => [[P('M50 8 94 86H6Z'), P('M50 22 82 80H18Z')], [R(46, 38, 8, 26, 3) + C(50, 72, 5), '']],
    };

    // Shapes: outline in a 256 box, where the symbol sits (cx, cy, size).
    const SHAPES = {
        heater:   { d: 'M38 34H218V118C218 176 178 212 128 232C78 212 38 176 38 118Z', cx: 128, cy: 118, s: 128 },
        kite:     { d: 'M128 18L222 52C222 140 188 198 128 240C68 198 34 140 34 52Z', cx: 128, cy: 112, s: 120 },
        round:    { d: 'M42 32H214V134C214 186 176 224 128 224C80 224 42 186 42 134Z', cx: 128, cy: 120, s: 128 },
        patch:    { d: 'M34 30H222V168L128 234L34 168Z', cx: 128, cy: 116, s: 124 },
        circle:   { d: 'M128 26A102 102 0 1 1 127.9 26Z', cx: 128, cy: 128, s: 132 },
        hex:      { d: poly(128, 128, 108, 6, -90), cx: 128, cy: 128, s: 128 },
        octagon:  { d: poly(128, 128, 108, 8, 22.5), cx: 128, cy: 128, s: 130 },
        diamond:  { d: 'M128 14L242 128L128 242L14 128Z', cx: 128, cy: 128, s: 112 },
        square:   { d: 'M54 32H202Q224 32 224 54V202Q224 224 202 224H54Q32 224 32 202V54Q32 32 54 32Z', cx: 128, cy: 128, s: 136 },
        pennant:  { d: 'M42 20H214V234L128 196L42 234Z', cx: 128, cy: 106, s: 120 },
        cog:      { d: gear(128, 128, 116, 98, 14), cx: 128, cy: 128, s: 116 },
        triangle: { d: 'M128 22L238 220H18Z', cx: 128, cy: 150, s: 104 },
        dogtag:   { d: 'M74 22H182Q214 22 214 54V202Q214 234 182 234H74Q42 234 42 202V54Q42 22 74 22Z', cx: 128, cy: 136, s: 120, hole: [128, 44, 9] },
        roundel:  { d: 'M128 18A110 110 0 1 1 127.9 18Z', cx: 128, cy: 128, s: 116, ring: true },
    };

    // Patterns: drawn in the secondary colour over the whole box, clipped to the shape.
    const stripes = (horizontal, w) => { let s = ''; for (let i = 0; i < 256; i += w * 2) s += horizontal ? R(0, i + w / 2, 256, w) : R(i + w / 2, 0, w, 256); return s; };
    const PATTERNS = {
        none: () => '',
        halves: () => R(128, 0, 128, 256),
        fess: () => R(0, 128, 256, 128),
        quarters: () => R(128, 0, 128, 128) + R(0, 128, 128, 128),
        per_bend: () => P('M0 0H256V256Z'),
        bend: () => P('M-20 30L30-20L276 226L226 276Z'),
        chevron: () => P('M0 182L128 96L256 182V230L128 144L0 230Z'),
        chief: () => R(0, 0, 256, 84),
        pales: () => stripes(false, 32),
        bars: () => stripes(true, 28),
        cross: () => R(104, 0, 48, 256) + R(0, 104, 256, 48),
        saltire: () => G('rotate(45 128 128)', R(106, -60, 44, 376) + R(-60, 106, 376, 44)),
        orle: (s) => `<path d="${s.d}" fill="none" stroke="currentColor" stroke-width="44"/>`,
        rays: () => { let s = ''; for (let i = 0; i < 16; i += 2) { const [x1, y1] = pt(128, 128, 260, i * 22.5), [x2, y2] = pt(128, 128, 260, (i + 1) * 22.5); s += P(`M128 128L${x1} ${y1}L${x2} ${y2}Z`); } return s; },
        hazard: () => { let s = ''; for (let i = -256; i < 256; i += 56) s += P(`M${i} 256L${i + 256} 0H${i + 284}L${i + 28} 256Z`); return s; },
        checker: () => { let s = ''; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) if ((x + y) % 2) s += R(x * 32, y * 32, 32, 32); return s; },
        camo: () => P('M20 40c20-20 50-10 60 10s-10 40-34 34S0 60 20 40ZM140 20c30-10 60 10 50 34s-40 20-54 6-20-30 4-40ZM180 120c26-6 50 14 44 40s-36 26-50 12-20-46 6-52ZM60 140c24-10 52 6 52 30s-30 40-52 30-24-50 0-60ZM100 220c20-10 46 0 48 20s-20 30-40 24-28-34-8-44ZM10 230c10-14 30-12 36 0s-6 26-20 26-24-12-16-26Z') + `<g opacity=".55">${P('M110 80c16-8 34 2 34 16s-18 22-32 16-18-24-2-32ZM200 60c14-4 30 6 28 18s-18 18-28 10-14-24 0-28ZM30 180c14-4 26 6 24 16s-16 16-26 10-10-22 2-26ZM170 200c14-6 30 2 30 14s-14 20-26 16-18-24-4-30Z')}</g>`,
        dots: () => { let s = ''; for (let y = 16; y < 256; y += 32) for (let x = (y / 32) % 2 ? 32 : 16; x < 256; x += 32) s += C(x, y, 6); return s; },
    };

    const BORDERS = ['none', 'thin', 'thick', 'double', 'rivets', 'stitched', 'barbed'];
    const WEAR = ['none', 'scuffed', 'weathered', 'battered', 'burnt', 'rust'];

    const SYMBOL_IDS = Object.keys(SYMBOLS), SHAPE_IDS = Object.keys(SHAPES), PATTERN_IDS = Object.keys(PATTERNS);
    const TAG_MAX = 4;

    const LABEL = {
        heater: 'Heater shield', kite: 'Kite shield', round: 'Round shield', patch: 'Patch', circle: 'Circle', hex: 'Hexagon', octagon: 'Octagon', diamond: 'Diamond', square: 'Plate', pennant: 'Pennant', cog: 'Cog', triangle: 'Warning sign', dogtag: 'Dog tag', roundel: 'Roundel',
        none: 'None', halves: 'Halves', fess: 'Split', quarters: 'Quarters', per_bend: 'Diagonal', bend: 'Band', chevron: 'Chevron', chief: 'Top band', pales: 'Stripes', bars: 'Bars', cross: 'Cross', saltire: 'Saltire', orle: 'Inner rim', rays: 'Rays', hazard: 'Hazard', checker: 'Checker', camo: 'Camo', dots: 'Dots',
        thin: 'Thin', thick: 'Thick', double: 'Double', rivets: 'Rivets', stitched: 'Stitched', barbed: 'Barbed',
        scuffed: 'Scuffed', weathered: 'Weathered', battered: 'Battered', burnt: 'Burnt', rust: 'Rust',
        skull: 'Skull', skull_bones: 'Skull and bones', ram_skull: 'Ram skull', wolf: 'Wolf', crow: 'Crow', snake: 'Snake', wings: 'Wings', winged_wheel: 'Winged wheel', eagle: 'Eagle', star: 'Star', star_ring: 'Ringed star', compass: 'Compass', chevrons: 'Chevrons', crossed_rifles: 'Crossed rifles', crosshair: 'Crosshair', bullets: 'Bullets', dagger: 'Dagger', axes: 'Crossed axes', hammer: 'Hammer', wrenches: 'Crossed wrenches', gear: 'Gear', pistons: 'Pistons', wheel: 'Wheel', flame: 'Flame', bolt: 'Bolt', biohazard: 'Biohazard', radiation: 'Radiation', fist: 'Fist', hand: 'Open hand', crown: 'Crown', eye: 'Eye', anchor: 'Anchor', sprout: 'Sprout', tree: 'Pine', house: 'Shelter', tower: 'Watchtower', mountain: 'Mountain', medical: 'Medical cross', heart: 'Lifeline', key: 'Key', warning: 'Warning',
    };

    const DEFAULT = { v: 1, shape: 'heater', pattern: 'none', symbol: 'skull', border: 'thick', wear: 'scuffed', primary: '#3a3f2c', secondary: '#24271b', accent: '#e08c46', tag: '' };

    function cleanTag(t) { return String(t || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, TAG_MAX); }

    // Same rules as the server: unknown ids fall back, colours must be #rrggbb.
    function normalize(spec) {
        let s = spec;
        if (typeof s === 'string') { try { s = JSON.parse(s); } catch (_) { s = null; } }
        s = (s && typeof s === 'object') ? s : {};
        const pick = (v, list, d) => (list.includes(v) ? v : d);
        const col = (v, d) => (HEX.test(String(v || '')) ? String(v).toLowerCase() : d);
        return {
            v: 1,
            shape: pick(s.shape, SHAPE_IDS, DEFAULT.shape),
            pattern: pick(s.pattern, PATTERN_IDS, DEFAULT.pattern),
            symbol: pick(s.symbol, SYMBOL_IDS, DEFAULT.symbol),
            border: pick(s.border, BORDERS, DEFAULT.border),
            wear: pick(s.wear, WEAR, DEFAULT.wear),
            primary: col(s.primary, DEFAULT.primary),
            secondary: col(s.secondary, DEFAULT.secondary),
            accent: col(s.accent, DEFAULT.accent),
            tag: cleanTag(s.tag),
        };
    }

    function hash(str) { let h = 2166136261; for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

    function shade(hex, amt) {
        const n = parseInt(hex.slice(1), 16);
        const ch = (v) => Math.max(0, Math.min(255, Math.round(amt < 0 ? v * (1 + amt) : v + (255 - v) * amt)));
        return '#' + [ch(n >> 16), ch((n >> 8) & 255), ch(n & 255)].map((v) => v.toString(16).padStart(2, '0')).join('');
    }

    function borderMarkup(s, shape, u) {
        const d = shape.d, a = s.accent, dark = shade(s.primary, -0.55);
        const clip = `clip-path="url(#${u}c)"`;
        switch (s.border) {
        case 'none': return `<path d="${d}" fill="none" stroke="${dark}" stroke-width="3" opacity=".7"/>`;
        case 'thin': return `<path d="${d}" fill="none" stroke="${a}" stroke-width="10" ${clip}/><path d="${d}" fill="none" stroke="${dark}" stroke-width="2.5"/>`;
        case 'thick': return `<path d="${d}" fill="none" stroke="${a}" stroke-width="22" ${clip}/><path d="${d}" fill="none" stroke="${dark}" stroke-width="3"/><path d="${d}" fill="none" stroke="${dark}" stroke-width="2" transform="translate(128 128) scale(.91) translate(-128 -128)" opacity=".8"/>`;
        case 'double': return `<path d="${d}" fill="none" stroke="${a}" stroke-width="12" ${clip}/><path d="${d}" fill="none" stroke="${a}" stroke-width="5" transform="translate(128 128) scale(.86) translate(-128 -128)"/><path d="${d}" fill="none" stroke="${dark}" stroke-width="2.5"/>`;
        case 'rivets': {
            let dots = '';
            const pathEl = global.document ? measure(d) : null;
            if (pathEl) {
                const len = pathEl.getTotalLength(), n = Math.max(10, Math.round(len / 34));
                for (let i = 0; i < n; i++) { const p = pathEl.getPointAtLength(len * i / n); const ix = 128 + (p.x - 128) * 0.93, iy = 128 + (p.y - 128) * 0.93; dots += `<circle cx="${f(ix)}" cy="${f(iy)}" r="4.2" fill="${shade(a, -0.35)}"/><circle cx="${f(ix - 1)}" cy="${f(iy - 1)}" r="2" fill="${shade(a, 0.35)}"/>`; }
            }
            return `<path d="${d}" fill="none" stroke="${a}" stroke-width="26" ${clip}/>${dots}<path d="${d}" fill="none" stroke="${dark}" stroke-width="3"/>`;
        }
        case 'stitched': return `<path d="${d}" fill="none" stroke="${shade(s.primary, -0.4)}" stroke-width="18" ${clip}/><path d="${d}" fill="none" stroke="${a}" stroke-width="3.5" stroke-dasharray="9 6" transform="translate(128 128) scale(.95) translate(-128 -128)"/><path d="${d}" fill="none" stroke="${dark}" stroke-width="2.5"/>`;
        case 'barbed': return `<path d="${d}" fill="none" stroke="${a}" stroke-width="14" ${clip}/><path d="${d}" fill="none" stroke="${a}" stroke-width="6" stroke-dasharray="2 14" transform="translate(128 128) scale(.9) translate(-128 -128)"/><path d="${d}" fill="none" stroke="${a}" stroke-width="2" transform="translate(128 128) scale(.9) translate(-128 -128)"/><path d="${d}" fill="none" stroke="${dark}" stroke-width="3"/>`;
        default: return '';
        }
    }

    // rivet spacing needs real path lengths, measured once per shape on a hidden svg
    const measured = {};
    function measure(d) {
        if (measured[d]) return measured[d];
        try {
            const ns = 'http://www.w3.org/2000/svg';
            let host = document.getElementById('bs-emblem-measure');
            if (!host) {
                host = document.createElementNS(ns, 'svg');
                host.setAttribute('id', 'bs-emblem-measure');
                host.setAttribute('style', 'position:absolute;width:0;height:0;overflow:hidden;visibility:hidden');
                (document.body || document.documentElement).appendChild(host);
            }
            const p = document.createElementNS(ns, 'path');
            p.setAttribute('d', d);
            host.appendChild(p);
            measured[d] = p;
            return p;
        } catch (_) { return null; }
    }

    function wearMarkup(s, u, seed) {
        if (s.wear === 'none') return { defs: '', mask: '', over: '' };
        const lvl = { scuffed: [3.6, -11, 8.3, 0.07], weathered: [3, -9, 6.6, 0.12], battered: [2.2, -7.5, 5.3, 0.17], burnt: [2.8, -9, 6.6, 0.12], rust: [3, -10, 7.4, 0.08] }[s.wear];
        const defs = `<filter id="${u}w" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="${lvl[0] * 0.09}" numOctaves="3" seed="${seed % 97}"/><feColorMatrix values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 ${lvl[1]} ${lvl[2]}"/></filter>` +
            `<filter id="${u}g" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".022" numOctaves="3" seed="${(seed >> 3) % 89}"/><feColorMatrix values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 2.6 -.9"/></filter>` +
            `<mask id="${u}m"><rect width="256" height="256" fill="#fff" filter="url(#${u}w)"/></mask>`;
        let over = `<rect width="256" height="256" filter="url(#${u}g)" opacity="${lvl[3]}" clip-path="url(#${u}c)"/>`;
        if (s.wear === 'burnt') over += `<radialGradient id="${u}b" cx="50%" cy="45%" r="62%"><stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#120a04" stop-opacity=".85"/></radialGradient><rect width="256" height="256" fill="url(#${u}b)" clip-path="url(#${u}c)"/>`;
        if (s.wear === 'rust') over += `<filter id="${u}r" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".05" numOctaves="3" seed="${(seed >> 5) % 71}"/><feColorMatrix values="0 0 0 0 .5 0 0 0 0 .25 0 0 0 0 .09 0 0 0 4.5 -2.6"/></filter><rect width="256" height="256" filter="url(#${u}r)" opacity=".8" clip-path="url(#${u}c)"/>`;
        return { defs, mask: `mask="url(#${u}m)"`, over };
    }

    function symbolMarkup(s, shape, u) {
        const layers = (SYMBOLS[s.symbol] || SYMBOLS.skull)();
        const tag = !!s.tag;
        const size = shape.s * (tag ? 0.86 : 1);
        const cy = shape.cy - (tag ? 16 : 0);
        const x = shape.cx - size / 2, y = cy - size / 2, k = size / 100;
        let defs = '', body = '';
        layers.forEach(([b, cut], i) => {
            if (cut) {
                defs += `<mask id="${u}s${i}" maskUnits="userSpaceOnUse" x="-20" y="-20" width="140" height="140"><rect x="-20" y="-20" width="140" height="140" fill="#fff"/><g fill="#000" stroke="none">${cut}</g></mask>`;
                body += `<g mask="url(#${u}s${i})">${b}</g>`;
            } else body += `<g>${b}</g>`;
        });
        // A dark rim around the symbol keeps it readable over busy patterns.
        defs += `<filter id="${u}o" x="-20%" y="-20%" width="140%" height="140%"><feMorphology in="SourceAlpha" operator="dilate" radius="${f(2.6 / k)}" result="d"/><feFlood flood-color="${shade(s.primary, -0.6)}" flood-opacity=".85"/><feComposite in2="d" operator="in" result="o"/><feMerge><feMergeNode in="o"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`;
        return { defs, svg: `<g transform="translate(${f(x)} ${f(y)}) scale(${f(k)})" fill="currentColor" color="${s.accent}" filter="url(#${u}o)">${body}</g>` };
    }

    function tagMarkup(s, shape) {
        if (!s.tag) return '';
        const y = Math.min(shape.cy + shape.s * 0.42, 206), w = 46 + s.tag.length * 26;
        const x0 = 128 - w / 2, x1 = 128 + w / 2, h = 34;
        const plate = `M${x0 - 14} ${y}L${x0} ${y - h / 2}H${x1}L${x1 + 14} ${y}L${x1} ${y + h / 2}H${x0}Z`;
        return `<path d="${plate}" fill="${s.accent}" stroke="${shade(s.primary, -0.55)}" stroke-width="3"/>` +
            `<text x="128" y="${f(y + 10.5)}" text-anchor="middle" font-family="'BS Stencil','Bahnschrift Condensed',Impact,sans-serif" font-size="30" letter-spacing="3" fill="${shade(s.primary, -0.35)}">${s.tag}</text>`;
    }

    // Main entry: spec -> svg string. opts.size sets width/height (default 100%), opts.title adds a tooltip.
    function render(spec, opts) {
        opts = opts || {};
        const s = normalize(spec);
        const shape = SHAPES[s.shape];
        const u = 'bse' + (++uidN) + '_';
        const seed = hash(JSON.stringify(s));
        const wear = wearMarkup(s, u, seed);
        const sym = symbolMarkup(s, shape, u);
        const hole = shape.hole ? `<circle cx="${shape.hole[0]}" cy="${shape.hole[1]}" r="${shape.hole[2]}" fill="#000"/>` : '';
        const size = opts.size ? ` width="${opts.size}" height="${opts.size}"` : '';
        const ring = shape.ring ? `<path d="${shape.d}" fill="none" stroke="${s.secondary}" stroke-width="56" clip-path="url(#${u}c)"/>` : '';
        const body = `<g ${wear.mask}>` +
            `<rect width="256" height="256" fill="${s.primary}" clip-path="url(#${u}c)"/>` +
            `<g fill="${s.secondary}" color="${s.secondary}" clip-path="url(#${u}c)">${PATTERNS[s.pattern](shape)}</g>` + ring +
            `<rect width="256" height="256" fill="url(#${u}l)" clip-path="url(#${u}c)"/>` +
            sym.svg + borderMarkup(s, shape, u) + tagMarkup(s, shape) + wear.over + '</g>';
        return `<svg class="bs-emblem" viewBox="0 0 256 256"${size} xmlns="http://www.w3.org/2000/svg" role="img">` +
            (opts.title ? `<title>${String(opts.title).replace(/[<>&"]/g, '')}</title>` : '') +
            `<defs><clipPath id="${u}c"><path d="${shape.d}"/></clipPath>` +
            `<mask id="${u}h"><rect width="256" height="256" fill="#fff"/>${hole}</mask>` +
            `<linearGradient id="${u}l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".14"/><stop offset=".45" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".32"/></linearGradient>` +
            wear.defs + sym.defs + `</defs><g mask="url(#${u}h)">${body}</g></svg>`;
    }

    // Old {mark, color} logos map onto the nearest symbol so nothing looks blank after the update.
    const LEGACY = { wolf: 'wolf', skull: 'skull', claw: 'axes', shield: 'star', eye: 'eye', bolt: 'bolt', crown: 'crown', serpent: 'snake' };
    function fromLegacy(logo, seedText) {
        let l = logo;
        if (typeof l === 'string') { try { l = JSON.parse(l); } catch (_) { l = null; } }
        if (!l || !LEGACY[l.mark]) return fallback(seedText || '');
        const c = HEX.test(l.color || '') ? l.color.toLowerCase() : '#e08c46';
        return normalize({ shape: 'heater', pattern: 'none', symbol: LEGACY[l.mark], border: 'thick', wear: 'scuffed', primary: shade(c, -0.72), secondary: shade(c, -0.82), accent: c });
    }

    // Factions without an emblem get a stable one from their id, never an empty slot.
    const FALLBACK_COLOURS = [['#3a3f2c', '#2a2e20', '#d9c58f'], ['#4a1e1a', '#2b1210', '#e2b07a'], ['#26303a', '#1a2129', '#c9d1d6'], ['#3d3226', '#2a2219', '#e08c46'], ['#2f3a33', '#202923', '#a7d29a'], ['#3b2a3d', '#271b29', '#d7b7e0']];
    function fallback(text) {
        const h = hash(String(text || 'faction'));
        const c = FALLBACK_COLOURS[h % FALLBACK_COLOURS.length];
        return normalize({ shape: SHAPE_IDS[(h >> 3) % 8], pattern: ['none', 'chief', 'halves', 'bend', 'orle'][(h >> 6) % 5], symbol: SYMBOL_IDS[(h >> 9) % SYMBOL_IDS.length], border: 'thick', wear: 'scuffed', primary: c[0], secondary: c[1], accent: c[2] });
    }

    // Preset gallery. The first four are the vanilla factions.
    const PRESETS = [
        { id: 'military', name: 'Iron Column', spec: { shape: 'patch', pattern: 'chief', symbol: 'crossed_rifles', border: 'stitched', wear: 'scuffed', primary: '#4b5531', secondary: '#323a20', accent: '#d8c690', tag: 'MIL' } },
        { id: 'rebels', name: 'Red Ruin', spec: { shape: 'kite', pattern: 'bend', symbol: 'skull', border: 'barbed', wear: 'battered', primary: '#7e221b', secondary: '#1c1514', accent: '#ece2cf', tag: 'REB' } },
        { id: 'civilians', name: 'Green Acre', spec: { shape: 'round', pattern: 'orle', symbol: 'sprout', border: 'thick', wear: 'weathered', primary: '#c9a24d', secondary: '#8f6f2a', accent: '#2c2b20', tag: 'CIV' } },
        { id: 'bikers', name: 'Steel Saints', spec: { shape: 'circle', pattern: 'rays', symbol: 'winged_wheel', border: 'rivets', wear: 'rust', primary: '#27303c', secondary: '#3c4b5f', accent: '#d9d4c7', tag: 'BKR' } },
        { id: 'deadhead', name: 'Dead Head', spec: { shape: 'circle', pattern: 'none', symbol: 'skull_bones', border: 'double', wear: 'weathered', primary: '#1d1c1a', secondary: '#2c2a26', accent: '#e9e1cf' } },
        { id: 'packwolf', name: 'Pack Law', spec: { shape: 'heater', pattern: 'per_bend', symbol: 'wolf', border: 'thick', wear: 'scuffed', primary: '#3c4650', secondary: '#2a3138', accent: '#e8e2d2' } },
        { id: 'quarantine', name: 'Quarantine', spec: { shape: 'triangle', pattern: 'none', symbol: 'biohazard', border: 'thick', wear: 'weathered', primary: '#d9a62e', secondary: '#b88a20', accent: '#1b1a16' } },
        { id: 'hotzone', name: 'Hot Zone', spec: { shape: 'octagon', pattern: 'hazard', symbol: 'radiation', border: 'thick', wear: 'battered', primary: '#e0b23a', secondary: '#1f1d18', accent: '#1f1d18' } },
        { id: 'murder', name: 'Murder of Crows', spec: { shape: 'pennant', pattern: 'chevron', symbol: 'crow', border: 'thin', wear: 'weathered', primary: '#22252a', secondary: '#3b1f24', accent: '#cfd2d6' } },
        { id: 'wrench', name: 'Grease Monkeys', spec: { shape: 'cog', pattern: 'none', symbol: 'wrenches', border: 'rivets', wear: 'rust', primary: '#5a4a35', secondary: '#3e3324', accent: '#e8b45c' } },
        { id: 'pistonhead', name: 'Pistonheads', spec: { shape: 'diamond', pattern: 'checker', symbol: 'pistons', border: 'thick', wear: 'scuffed', primary: '#1f1f1f', secondary: '#383838', accent: '#e05a2a' } },
        { id: 'medic', name: 'Last Aid', spec: { shape: 'roundel', pattern: 'none', symbol: 'medical', border: 'thin', wear: 'scuffed', primary: '#e6dfcf', secondary: '#9c2b22', accent: '#9c2b22' } },
        { id: 'lifeline', name: 'Lifeline', spec: { shape: 'hex', pattern: 'orle', symbol: 'heart', border: 'thin', wear: 'scuffed', primary: '#2a3a3f', secondary: '#1d282c', accent: '#e46a5c' } },
        { id: 'pyre', name: 'The Pyre', spec: { shape: 'kite', pattern: 'fess', symbol: 'flame', border: 'thick', wear: 'burnt', primary: '#2a1d16', secondary: '#5a1d10', accent: '#f08a2a' } },
        { id: 'thunder', name: 'Live Wire', spec: { shape: 'square', pattern: 'bend', symbol: 'bolt', border: 'double', wear: 'scuffed', primary: '#202a3a', secondary: '#2f3e57', accent: '#f2d34a' } },
        { id: 'crown', name: 'Ash Crown', spec: { shape: 'heater', pattern: 'quarters', symbol: 'crown', border: 'double', wear: 'weathered', primary: '#3b1f3d', secondary: '#291629', accent: '#e2bd63' } },
        { id: 'watcher', name: 'The Watch', spec: { shape: 'circle', pattern: 'orle', symbol: 'eye', border: 'thin', wear: 'scuffed', primary: '#1e2a26', secondary: '#2e3d36', accent: '#b9e0b0' } },
        { id: 'harbor', name: 'Dead Harbor', spec: { shape: 'round', pattern: 'bars', symbol: 'anchor', border: 'thick', wear: 'rust', primary: '#1f3140', secondary: '#273d50', accent: '#e9dcc0' } },
        { id: 'pines', name: 'Pine Ridge', spec: { shape: 'pennant', pattern: 'none', symbol: 'tree', border: 'stitched', wear: 'weathered', primary: '#2d3b2b', secondary: '#202a1f', accent: '#d9cfa6' } },
        { id: 'summit', name: 'High Ground', spec: { shape: 'patch', pattern: 'fess', symbol: 'mountain', border: 'stitched', wear: 'scuffed', primary: '#4a5560', secondary: '#323a42', accent: '#eae6dc' } },
        { id: 'fist', name: 'Uprising', spec: { shape: 'square', pattern: 'pales', symbol: 'fist', border: 'thick', wear: 'battered', primary: '#8b2a1e', secondary: '#701f16', accent: '#f1e7d2' } },
        { id: 'axe', name: 'Splitters', spec: { shape: 'kite', pattern: 'saltire', symbol: 'axes', border: 'barbed', wear: 'battered', primary: '#3c2a1e', secondary: '#2a1d14', accent: '#cdbb98' } },
        { id: 'snake', name: 'Viper Nest', spec: { shape: 'diamond', pattern: 'none', symbol: 'snake', border: 'thin', wear: 'weathered', primary: '#2a3a1f', secondary: '#1d2915', accent: '#c6d36b' } },
        { id: 'sight', name: 'Overwatch', spec: { shape: 'dogtag', pattern: 'none', symbol: 'crosshair', border: 'thin', wear: 'scuffed', primary: '#8f8c83', secondary: '#6e6b63', accent: '#1d1c19' } },
        { id: 'ram', name: 'Ram Clan', spec: { shape: 'heater', pattern: 'chevron', symbol: 'ram_skull', border: 'thick', wear: 'weathered', primary: '#5b4630', secondary: '#3f3021', accent: '#efe4cc' } },
        { id: 'eagle', name: 'Old Republic', spec: { shape: 'roundel', pattern: 'none', symbol: 'eagle', border: 'double', wear: 'weathered', primary: '#1f2b45', secondary: '#7c2620', accent: '#e8e0c8' } },
        { id: 'stars', name: 'Ranger Star', spec: { shape: 'circle', pattern: 'none', symbol: 'star_ring', border: 'rivets', wear: 'scuffed', primary: '#5c4b32', secondary: '#423523', accent: '#e9c873' } },
        { id: 'compass', name: 'Wayfinders', spec: { shape: 'octagon', pattern: 'cross', symbol: 'compass', border: 'thin', wear: 'scuffed', primary: '#2e3340', secondary: '#3a4152', accent: '#e8d8a8' } },
        { id: 'tower', name: 'Last Light', spec: { shape: 'patch', pattern: 'rays', symbol: 'tower', border: 'stitched', wear: 'weathered', primary: '#2b2a35', secondary: '#3a394a', accent: '#f0c060' } },
        { id: 'shelter', name: 'Homestead', spec: { shape: 'square', pattern: 'chief', symbol: 'house', border: 'thick', wear: 'scuffed', primary: '#6b4a2b', secondary: '#4c341e', accent: '#efe2c4' } },
        { id: 'key', name: 'Lockkeepers', spec: { shape: 'dogtag', pattern: 'bars', symbol: 'key', border: 'double', wear: 'rust', primary: '#3a3328', secondary: '#4a4234', accent: '#d7b46a' } },
        { id: 'grit', name: 'Grit Battalion', spec: { shape: 'patch', pattern: 'camo', symbol: 'chevrons', border: 'stitched', wear: 'battered', primary: '#4d5236', secondary: '#363a25', accent: '#e5d9a8' } },
        { id: 'hammer', name: 'Rebuilders', spec: { shape: 'hex', pattern: 'halves', symbol: 'hammer', border: 'thick', wear: 'scuffed', primary: '#41505a', secondary: '#2f3b43', accent: '#e9a34f' } },
        { id: 'open', name: 'Open Hand', spec: { shape: 'round', pattern: 'dots', symbol: 'hand', border: 'thin', wear: 'weathered', primary: '#e1d6bc', secondary: '#cdbf9f', accent: '#5a3b26' } },
        { id: 'bullets', name: 'Brass Rain', spec: { shape: 'heater', pattern: 'none', symbol: 'bullets', border: 'rivets', wear: 'scuffed', primary: '#2c2a26', secondary: '#3a3731', accent: '#d9a653' } },
        { id: 'dagger', name: 'Night Knives', spec: { shape: 'kite', pattern: 'halves', symbol: 'dagger', border: 'thin', wear: 'weathered', primary: '#16181c', secondary: '#2a1316', accent: '#d4d7db' } },
    ].map((p) => ({ id: p.id, name: p.name, spec: normalize(p.spec) }));

    const catalog = {
        shapes: SHAPE_IDS, patterns: PATTERN_IDS, symbols: SYMBOL_IDS, borders: BORDERS, wear: WEAR, tagMax: TAG_MAX,
        label: (id) => LABEL[id] || String(id).replace(/_/g, ' '),
    };

    global.BSEmblem = { render, normalize, fromLegacy, fallback, presets: PRESETS, catalog, shade, cleanTag };
})(window);
