"""analyze.py – objective checks of rendered music (loudness arc, band balance, spectrogram)"""
import sys, numpy as np, soundfile as sf, scipy.signal as sps
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pyloudnorm as pyln

def analyze(path, png, sec=None):
    x, sr = sf.read(path)
    m = x.mean(axis=1)
    meter = pyln.Meter(sr)
    win = 3.0
    st = []
    for i in range(0, len(x) - int(win*sr), int(win*sr)):
        try: st.append(meter.integrated_loudness(x[i:i+int(win*sr)]))
        except Exception: st.append(-70)
    print("short-term LUFS per 3s:", " ".join(f"{v:.0f}" for v in st))
    f, P = sps.welch(m, sr, nperseg=8192)
    bands = [(20,60,'sub'),(60,200,'bass'),(200,500,'lowmid'),(500,2000,'mid'),(2000,6000,'presence'),(6000,20000,'air')]
    tot = P.sum()
    print("band energy %:", " ".join(f"{n}={100*P[(f>=a)&(f<b)].sum()/tot:.1f}" for a,b,n in bands))
    side = (x[:,0]-x[:,1])/2; mid=(x[:,0]+x[:,1])/2
    print(f"stereo width (side/mid rms): {np.sqrt(np.mean(side**2))/np.sqrt(np.mean(mid**2)):.2f}  crest dB: {20*np.log10(np.abs(m).max()/np.sqrt(np.mean(m**2))):.1f}")
    ff, t, S = sps.spectrogram(m, sr, nperseg=4096, noverlap=2048)
    fig, ax = plt.subplots(2,1, figsize=(16,8), gridspec_kw={'height_ratios':[1,3]})
    ax[0].plot(np.arange(len(st))*win, st); ax[0].set_ylim(-40,-5); ax[0].grid(True)
    ax[1].pcolormesh(t, ff, 10*np.log10(S+1e-14), shading='auto', vmin=-120, vmax=-40, cmap='magma')
    ax[1].set_yscale('symlog', linthresh=200); ax[1].set_ylim(30, 18000)
    fig.tight_layout(); fig.savefig(png, dpi=55)

if __name__ == "__main__":
    analyze(sys.argv[1], sys.argv[2])
