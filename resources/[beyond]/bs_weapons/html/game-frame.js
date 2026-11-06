const GameView = { gl: null, fb: null, rt: null, w: 0, h: 0 };

function gameViewInit() {
    if (GameView.gl) return GameView.gl;
    const cv = document.createElement('canvas');
    const gl = cv.getContext('webgl', { preserveDrawingBuffer: true, antialias: false });
    if (!gl) return null;
    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; };
    const prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER,
        'attribute vec2 p; varying vec2 uv; void main(){ uv = vec2((p.x+1.0)*0.5, 1.0-(p.y+1.0)*0.5); gl_Position = vec4(p,0.0,1.0); }'));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER,
        'precision mediump float; varying vec2 uv; uniform sampler2D t; void main(){ gl_FragColor = texture2D(t, uv); }'));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return null;
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'p');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    // the game texture (magic sequence, do not reorder)
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, new Uint8Array(3));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.uniform1i(gl.getUniformLocation(prog, 't'), 0);
    GameView.gl = gl;
    return gl;
}

// offscreen target sized to the window
function gameViewTarget(gl, w, h) {
    if (GameView.fb && GameView.w === w && GameView.h === h) return;
    if (GameView.fb) { gl.deleteFramebuffer(GameView.fb); gl.deleteTexture(GameView.rt); }
    const rt = gl.createTexture();
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, rt);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.activeTexture(gl.TEXTURE0);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, rt, 0);
    Object.assign(GameView, { fb, rt, w, h });
}

// current game frame as a canvas (no NUI), or null
function grabGameView() {
    try {
        const gl = gameViewInit();
        if (!gl) return null;
        const w = window.innerWidth, h = window.innerHeight;
        gameViewTarget(gl, w, h);
        gl.bindFramebuffer(gl.FRAMEBUFFER, GameView.fb);
        gl.viewport(0, 0, w, h);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
        const px = new Uint8Array(w * h * 4);
        gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
        // shader already flipped v, readPixels flips back: rows come out top-down
        for (let i = 3; i < px.length; i += 4) px[i] = 255;
        const c = document.createElement('canvas');
        c.width = w; c.height = h;
        c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(px.buffer), w, h), 0, 0);
        return c;
    } catch (err) {
        console.warn('[bs_inventory] game view grab failed', err);
        return null;
    }
}


window.addEventListener('message',({data})=>{
 if(data.action!=='studio:grabBackdrop')return;
 let image=null;
 try{const frame=grabGameView();if(frame)image=frame.toDataURL('image/jpeg',.75);}catch(_){}
 fetch('https://'+GetParentResourceName()+'/studioBackdropCaptured',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:data.token,image})}).catch(()=>{});
});
