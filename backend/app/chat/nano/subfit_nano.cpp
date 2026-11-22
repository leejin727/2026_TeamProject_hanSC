// subfit_nano.cpp — SubFit 챗봇 의도 판단기 C++ 실행기 (2026-11-19) · 외부 라이브러리 없음 · Linux/Windows/macOS 공용
//
//   입력 = rules.py 가 역 자리를 ◆로 바꾸고 소문자로 만든 문장 한 줄 (UTF-8)
//   → 한글을 초성·중성·종성 자모로 나눔 → int8 양방향 인코더 한 번 → <cls> 자리에서 머리 3개
//      의도(26가지) · 기준(none/time/transfers) · 흐름(new/follow/reverse)
//   어휘에 없는 글자(이모지·한자 등)는 "칸" 512개 중 하나 (코드값 % 512) — 학습(tok.py)과 같은 계산
//   계산 규칙은 학습(train.py int8 모드)과 같다: 가중치 행마다 int8 · 입력 벡터마다 int8 · 곱의 합은 정수(int32)
//                                             LayerNorm · GELU · softmax 는 float32
//
//   Linux/macOS: g++ -O2 -std=c++17 -o subfit_nano subfit_nano.cpp
//   Windows    : cl /O2 /EHsc /utf-8 subfit_nano.cpp   또는  g++ -O2 -std=c++17 -static -o subfit_nano.exe subfit_nano.cpp
//   ./subfit_nano subfit_nano.bin        # 표준입력 한 줄 → "의도<TAB>확신<TAB>기준<TAB>확신<TAB>흐름<TAB>확신"
//   ./subfit_nano subfit_nano.bin --bench 1000
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <chrono>
#include <iostream>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
using namespace std;

struct Mat { int r = 0, c = 0; vector<int8_t> q; vector<float> s; };
struct Layer { vector<float> l1w, l1b, l2w, l2b, bqkv, bo, b1, b2; Mat qkv, o, f1, f2; };
struct Head { string name; vector<string> labels; Mat w; vector<float> b; };
struct Model {
    uint32_t d, L, h, ff, ctx, V, nheads;
    vector<string> vocab; unordered_map<string, int> stoi; int bucket0 = -1, nbucket = 512;
    Mat tok, pos; vector<Layer> lay; vector<float> lfw, lfb; vector<Head> heads;
};
static const uint8_t *P;
template <class T> static T rd() { T v; memcpy(&v, P, sizeof(T)); P += sizeof(T); return v; }
static vector<float> rdv(int n) { vector<float> v(n); memcpy(v.data(), P, 4 * (size_t)n); P += 4 * (size_t)n; return v; }
static Mat rdm(int r, int c) { Mat m; m.r = r; m.c = c; m.q.resize((size_t)r * c); memcpy(m.q.data(), P, (size_t)r * c); P += (size_t)r * c; m.s = rdv(r); return m; }
static string rds() { int n = rd<uint8_t>(); string s((const char *)P, n); P += n; return s; }

static bool load(const char *fn, Model &M, vector<uint8_t> &buf) {
    FILE *f = fopen(fn, "rb"); if (!f) return false;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET); buf.resize(n);
    if (fread(buf.data(), 1, n, f) != (size_t)n) { fclose(f); return false; } fclose(f);
    P = buf.data(); if (memcmp(P, "SFN1", 4)) return false; P += 4;
    M.d = rd<uint32_t>(); M.L = rd<uint32_t>(); M.h = rd<uint32_t>(); M.ff = rd<uint32_t>(); M.ctx = rd<uint32_t>();
    M.V = rd<uint32_t>(); M.nheads = rd<uint32_t>();
    for (uint32_t i = 0; i < M.V; i++) { M.vocab.push_back(rds()); M.stoi[M.vocab.back()] = i; }
    auto b0 = M.stoi.find("<b0>"); if (b0 != M.stoi.end()) M.bucket0 = b0->second;
    for (uint32_t i = 0; i < M.nheads; i++) {
        Head H; H.name = rds(); uint32_t n = rd<uint32_t>();
        for (uint32_t k = 0; k < n; k++) H.labels.push_back(rds());
        M.heads.push_back(H);
    }
    int d = M.d, F = M.ff * M.d;
    M.tok = rdm(M.V, d); M.pos = rdm(M.ctx, d);
    for (uint32_t i = 0; i < M.L; i++) {
        Layer Ly; Ly.l1w = rdv(d); Ly.l1b = rdv(d);
        Ly.qkv = rdm(3 * d, d); Ly.bqkv = rdv(3 * d); Ly.o = rdm(d, d); Ly.bo = rdv(d);
        Ly.l2w = rdv(d); Ly.l2b = rdv(d);
        Ly.f1 = rdm(F, d); Ly.b1 = rdv(F); Ly.f2 = rdm(d, F); Ly.b2 = rdv(d);
        M.lay.push_back(std::move(Ly));
    }
    M.lfw = rdv(d); M.lfb = rdv(d);
    for (auto &H : M.heads) { H.w = rdm(H.labels.size(), d); H.b = rdv(H.labels.size()); }
    return (size_t)(P - buf.data()) == buf.size();
}

// y = int8(x) · int8(W)ᵀ (정수 합) × s × ws + b      (반올림 = 짝수 쪽, torch.round 와 같다)
static void lin(const float *x, int n, const Mat &W, const float *b, float *y) {
    float mx = 0; for (int i = 0; i < n; i++) mx = max(mx, fabsf(x[i]));
    float s = max(mx / 127.0f, 1e-8f);
    static thread_local vector<int8_t> xq; xq.resize(n);
    for (int i = 0; i < n; i++) { float v = nearbyintf(x[i] / s); xq[i] = (int8_t)max(-127.0f, min(127.0f, v)); }
    for (int r = 0; r < W.r; r++) {
        const int8_t *w = &W.q[(size_t)r * n]; int32_t acc = 0;
        for (int i = 0; i < n; i++) acc += (int32_t)xq[i] * w[i];
        y[r] = (float)acc * s * W.s[r] + b[r];
    }
}
static void lnorm(const float *x, int n, const float *w, const float *b, float *y) {
    float m = 0; for (int i = 0; i < n; i++) m += x[i]; m /= n;
    float v = 0; for (int i = 0; i < n; i++) v += (x[i] - m) * (x[i] - m); v /= n;
    float r = 1.0f / sqrtf(v + 1e-5f);
    for (int i = 0; i < n; i++) y[i] = (x[i] - m) * r * w[i] + b[i];
}

// ═════════ 글자 → 번호 (tok.ids 와 같다) ═════════
static void put_cp(string &o, uint32_t c) {
    if (c < 0x80) o += (char)c;
    else if (c < 0x800) { o += (char)(0xC0 | (c >> 6)); o += (char)(0x80 | (c & 63)); }
    else if (c < 0x10000) { o += (char)(0xE0 | (c >> 12)); o += (char)(0x80 | ((c >> 6) & 63)); o += (char)(0x80 | (c & 63)); }
    else { o += (char)(0xF0 | (c >> 18)); o += (char)(0x80 | ((c >> 12) & 63)); o += (char)(0x80 | ((c >> 6) & 63)); o += (char)(0x80 | (c & 63)); }
}
static vector<int> encode(const Model &M, const string &s) {
    vector<int> ids{M.stoi.at("<cls>")};
    int unk = M.stoi.at("<unk>");
    auto id_of = [&](uint32_t c) {
        string o; put_cp(o, c);
        auto it = M.stoi.find(o);
        if (it != M.stoi.end()) return it->second;
        return M.bucket0 >= 0 ? M.bucket0 + (int)(c % M.nbucket) : unk;
    };
    for (size_t i = 0; i < s.size();) {
        unsigned char c0 = s[i]; uint32_t c; size_t n;
        if (c0 < 0x80) { c = c0; n = 1; }
        else if ((c0 >> 5) == 6) { c = c0 & 31; n = 2; }
        else if ((c0 >> 4) == 14) { c = c0 & 15; n = 3; }
        else { c = c0 & 7; n = 4; }
        for (size_t k = 1; k < n && i + k < s.size(); k++) c = (c << 6) | (s[i + k] & 63);
        i += n;
        if (c >= 0xAC00 && c <= 0xD7A3) {
            uint32_t k = c - 0xAC00;
            ids.push_back(id_of(0x1100 + k / 588)); ids.push_back(id_of(0x1161 + (k % 588) / 28));
            if (k % 28) ids.push_back(id_of(0x11A8 + k % 28 - 1));
            continue;
        }
        if (c == '\t' || c == '\n' || c == '\r' || c == 0x3000) c = ' ';
        if (c >= 'A' && c <= 'Z') c += 32;
        ids.push_back(id_of(c));
    }
    if (ids.size() > M.ctx) ids.resize(M.ctx);
    return ids;
}

// → 머리마다 (고른 라벨 번호, 확률)
static vector<pair<int, float>> judge(const Model &M, const string &text) {
    vector<int> ids = encode(M, text);
    int d = M.d, H = M.h, hd = d / H, F = M.ff * d, T = ids.size();
    vector<float> x((size_t)T * d), a(d), qkv((size_t)T * 3 * d), att((size_t)T * d), f(F), t2(d), p(T);
    for (int t = 0; t < T; t++)
        for (int i = 0; i < d; i++)
            x[(size_t)t * d + i] = (float)M.tok.q[(size_t)ids[t] * d + i] * M.tok.s[ids[t]] + (float)M.pos.q[(size_t)t * d + i] * M.pos.s[t];
    float sc = 1.0f / sqrtf((float)hd);
    for (uint32_t l = 0; l < M.L; l++) {
        const Layer &Ly = M.lay[l];
        for (int t = 0; t < T; t++) { lnorm(&x[(size_t)t * d], d, Ly.l1w.data(), Ly.l1b.data(), a.data()); lin(a.data(), d, Ly.qkv, Ly.bqkv.data(), &qkv[(size_t)t * 3 * d]); }
        for (int t = 0; t < T; t++)
            for (int hh = 0; hh < H; hh++) {
                const float *q = &qkv[(size_t)t * 3 * d + hh * hd]; float mx = -1e30f;
                for (int j = 0; j < T; j++) { const float *k = &qkv[(size_t)j * 3 * d + d + hh * hd]; float s = 0; for (int e = 0; e < hd; e++) s += q[e] * k[e]; p[j] = s * sc; mx = max(mx, p[j]); }
                float z = 0; for (int j = 0; j < T; j++) { p[j] = expf(p[j] - mx); z += p[j]; }
                for (int e = 0; e < hd; e++) { float s = 0; for (int j = 0; j < T; j++) s += p[j] * qkv[(size_t)j * 3 * d + 2 * d + hh * hd + e]; att[(size_t)t * d + hh * hd + e] = s / z; }
            }
        for (int t = 0; t < T; t++) {
            float *xt = &x[(size_t)t * d];
            lin(&att[(size_t)t * d], d, Ly.o, Ly.bo.data(), t2.data()); for (int i = 0; i < d; i++) xt[i] += t2[i];
            lnorm(xt, d, Ly.l2w.data(), Ly.l2b.data(), a.data());
            lin(a.data(), d, Ly.f1, Ly.b1.data(), f.data());
            for (int i = 0; i < F; i++) f[i] = 0.5f * f[i] * (1.0f + erff(f[i] / sqrtf(2.0f)));
            lin(f.data(), F, Ly.f2, Ly.b2.data(), t2.data()); for (int i = 0; i < d; i++) xt[i] += t2[i];
        }
    }
    lnorm(&x[0], d, M.lfw.data(), M.lfb.data(), a.data());      // <cls> 자리만 쓴다
    vector<pair<int, float>> out;
    for (auto &Hd : M.heads) {
        vector<float> li(Hd.labels.size()); lin(a.data(), d, Hd.w, Hd.b.data(), li.data());
        int best = max_element(li.begin(), li.end()) - li.begin();
        float z = 0; for (float v : li) z += expf(v - li[best]);
        out.push_back({best, 1.0f / z});
    }
    return out;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);   // 줄 끝 \r\n 바꿈 막기 (UTF-8 바이트 그대로)
#endif
    if (argc < 2) { fprintf(stderr, "usage: %s subfit_nano.bin [--bench N]\n", argv[0]); return 1; }
    Model M; vector<uint8_t> buf;
    if (!load(argv[1], M, buf)) { fprintf(stderr, "model load failed\n"); return 1; }
    if (argc >= 4 && string(argv[2]) == "--bench") {
        int n = atoi(argv[3]);
        string tx = "\xE2\x97\x86\xEC\x97\x90\xEC\x84\x9C \xE2\x97\x86\xEA\xB9\x8C\xEC\xA7\x80 \xEC\x96\xB4\xEB\x96\xBB\xEA\xB2\x8C \xEA\xB0\x80?";  // "◆에서 ◆까지 어떻게 가?"
        auto t0 = chrono::steady_clock::now(); vector<pair<int, float>> r;
        for (int i = 0; i < n; i++) r = judge(M, tx);
        double ms = chrono::duration<double, milli>(chrono::steady_clock::now() - t0).count() / n;
        printf("%s %.4f\n%.3f ms per sentence (1 core, %d runs avg)\n", M.heads[0].labels[r[0].first].c_str(), r[0].second, ms, n);
        return 0;
    }
    string line;
    while (getline(cin, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        auto r = judge(M, line);
        for (size_t i = 0; i < r.size(); i++)
            printf("%s%s\t%.4f", i ? "\t" : "", M.heads[i].labels[r[i].first].c_str(), r[i].second);
        printf("\n"); fflush(stdout);
    }
}
