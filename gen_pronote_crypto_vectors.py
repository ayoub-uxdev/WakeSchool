#!/usr/bin/env python3
"""Génère PronoteCryptoFixtures.swift en exécutant le VRAI code de pronotepy 2.15.7.

Usage : PYTHONPATH=<chemin>/pronotepy-2.15.7 python3 gen_pronote_crypto_vectors.py > PronoteCryptoFixtures.swift
Dépendances : pycryptodome, requests, beautifulsoup4, autoslot.
"""
import sys
from Crypto.Hash import MD5, SHA256
from Crypto.PublicKey import RSA
from Crypto.Util import Padding
from pronotepy.pronoteAPI import _Encryption, _Communication, _enBytes
from pronotepy.exceptions import CryptoError

def hx(b): return b.hex()
out = []
w = out.append

def swift_str(s):
    r = ""
    for ch in s:
        o = ord(ch)
        if ch == '"': r += '\\"'
        elif ch == '\\': r += '\\\\'
        elif ch == '\n': r += '\\n'
        elif ch == '\t': r += '\\t'
        elif ch == '\r': r += '\\r'
        elif 0x20 <= o < 0x7f: r += ch
        else: r += '\\u{%X}' % o
    return '"' + r + '"'

def opt(v): return 'nil' if v is None else '"%s"' % v

w("// GÉNÉRÉ par tools/gen_pronote_crypto_vectors.py en exécutant pronotepy 2.15.7 (_Encryption, _Communication.after_auth, _enBytes,")
w("// Crypto.Hash.MD5/SHA256, Crypto.Util.Padding, bytes.fromhex). Ne pas éditer à la main.")
w("import Foundation")
w("")
w("struct PCHashVector { let inputHex: String; let md5Hex: String; let sha256Hex: String }")
w("struct PCPadVector { let inputHex: String; let paddedHex: String }")
w("struct PCUnpadVector { let inputHex: String; let unpaddedHex: String? }")
w("struct PCAESVector { let name: String; let keySeedHex: String?; let ivHex: String; let finalKeyHex: String; let plaintextHex: String; let ciphertextHex: String }")
w("struct PCAESFailureVector { let name: String; let keySeedHex: String?; let ivHex: String; let ciphertextHex: String }")
w("struct PCHexDecodeVector { let input: String; let expectedHex: String? }")
w("struct PCByteListVector { let input: String; let expectedHex: String? }")
w("struct PCLoginVector { let name: String; let username: String; let password: String; let alea: String; let ivTempHex: String; let challenge: String; let ent: Bool; let sha256UpperHex: String; let authKeyHex: String; let ivHex: String; let challengeCipherHex: String; let cle: String; let cleCipherHex: String; let finalKeyHex: String }")
w("struct PCRSAVector { let name: String; let messageHex: String; let paddingHex: String; let ciphertextHex: String }")
w("")
w("enum PronoteCryptoFixtures {")

# ---- hashes
inputs = [b"", b"abc", b"Pronote", "mötdépässe€".encode(), bytes(range(256)), b"a"*55, b"a"*56, b"a"*64]
w("    static let hashes: [PCHashVector] = [")
for i in inputs:
    w('        PCHashVector(inputHex: "%s", md5Hex: "%s", sha256Hex: "%s"),' % (hx(i), hx(MD5.new(i).digest()), SHA256.new(i).hexdigest()))
w("    ]")
w('    static let md5OfEmptyHex = "%s"  // _Encryption().aes_key par défaut (MD5.new().digest())' % hx(MD5.new().digest()))

# ---- padding
w("    static let pads: [PCPadVector] = [")
for n in (0,1,15,16,17,31,32,33):
    d = bytes((i*7+3) & 0xff for i in range(n))
    w('        PCPadVector(inputHex: "%s", paddedHex: "%s"),' % (hx(d), hx(Padding.pad(d,16))))
w("    ]")
def try_unpad(b):
    try: return hx(Padding.unpad(b,16))
    except ValueError: return None
cases = [b"", b"\x01", bytes(16), bytes([5])*11+bytes([7])*5, bytes(15)+b"\x11", bytes(15)+b"\x01", bytes(15)+b"\x10",
         bytes([16])*16, bytes(14)+b"\x02\x02", bytes(13)+b"\x01\x03\x03", bytes(12)+b"\x04\x04\x04\x04", bytes(12)+b"\x04\x03\x04\x04",
         b"abcdefghijklmnop"+bytes([16])*16, b"x"*20+bytes([4])*4, bytes([4])*3+b"\x00"*0]
w("    static let unpads: [PCUnpadVector] = [")
for c in cases:
    w('        PCUnpadVector(inputHex: "%s", unpaddedHex: %s),' % (hx(c), opt(try_unpad(c))))
w("    ]")

# ---- AES via _Encryption réel
def mk(keyseed, iv):
    e = _Encryption()
    e.aes_iv = iv
    if keyseed is not None: e.aes_set_key(keyseed)
    return e
iv0 = bytes(16)
iv1 = MD5.new(bytes(range(16))).digest()
iv2 = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
pts = {"vide": b"", "1octet": b"A", "15": b"B"*15, "16": b"C"*16, "17": b"D"*17, "32": b"E"*32,
       "json": b'{"_Signature_":{"onglet":7},"donnees":{"N":"abc","Actif":true}}', "utf8": "é€ ñ 中文".encode()}
aes = []
w("    static let aes: [PCAESVector] = [")
for kname, seed in (("defaut", None), ("pin", b"1234"), ("login", b"eleve.test"+SHA256.new(b"xYz9motdepasse").hexdigest().upper().encode())):
    for iname, iv in (("iv0", iv0), ("ivmd5", iv1), ("ivseq", iv2)):
        for pname, p in pts.items():
            e = mk(seed, iv)
            ct = e.aes_encrypt(p)
            assert e.aes_decrypt(ct) == p
            w('        PCAESVector(name: "%s/%s/%s", keySeedHex: %s, ivHex: "%s", finalKeyHex: "%s", plaintextHex: "%s", ciphertextHex: "%s"),' % (kname, iname, pname, opt(hx(seed) if seed is not None else None), hx(iv), hx(e.aes_key), hx(p), hx(ct)))
w("    ]")

# ---- AES : échecs (CryptoError dans pronotepy)
from Crypto.Cipher import AES
def raw_ct(key, iv, plain_padded): return AES.new(key, AES.MODE_CBC, iv).encrypt(plain_padded)
fails = []
e = mk(b"1234", iv0)
good = e.aes_encrypt(b"hello pronote")
other = mk(b"0000", iv0)
fails.append(("mauvaise clé", b"0000", iv0, good))
fails.append(("longueur non multiple de 16", b"1234", iv0, good[:-1]))
fails.append(("vide", b"1234", iv0, b""))
fails.append(("15 octets", b"1234", iv0, bytes(15)))
k = e.aes_key
fails.append(("pad = 0", b"1234", iv0, raw_ct(k, iv0, bytes(16))))
fails.append(("pad = 17", b"1234", iv0, raw_ct(k, iv0, bytes(15)+b"\x11")))
fails.append(("pad incohérent", b"1234", iv0, raw_ct(k, iv0, bytes(13)+b"\x01\x03\x03")))
fails.append(("mauvais IV (1er bloc)", b"1234", iv2, good))
w("    static let aesFailures: [PCAESFailureVector] = [")
for name, seed, iv, ct in fails:
    ee = mk(seed, iv)
    try:
        r = ee.aes_decrypt(ct)
        raise SystemExit("ATTENDU: CryptoError pour %s, obtenu %r" % (name, r))
    except CryptoError:
        pass
    w('        PCAESFailureVector(name: %s, keySeedHex: "%s", ivHex: "%s", ciphertextHex: "%s"),' % (swift_str(name), hx(seed), hx(iv), hx(ct)))
w("    ]")

# ---- hex
hexcases = ["", "00", "ab", "AB", "aBcD09", "ab cd", " ab\tcd\n01\r\x0b\x0c ", "abc", "a b", "zz", "0x12", "gh", "ab,cd", "é1", "ab\u00a0cd", "  ", "0", "123"]
w("    static let hexDecodes: [PCHexDecodeVector] = [")
for c in hexcases:
    try: r = hx(bytes.fromhex(c))
    except ValueError: r = None
    w('        PCHexDecodeVector(input: %s, expectedHex: %s),' % (swift_str(c), opt(r)))
w("    ]")
w('    static let hexEncodeInputHex = "%s"' % hx(bytes([0,1,15,16,127,128,171,205,239,255])))
w('    static let hexEncodeLower = "%s"' % bytes([0,1,15,16,127,128,171,205,239,255]).hex())
w('    static let hexEncodeUpper = "%s"' % bytes([0,1,15,16,127,128,171,205,239,255]).hex().upper())

bl = ["1,2,3", "0", "255", "4, 5 ,255", " 7 ", "+5,-0", "1_0,2", "", "1,,2", "1,2,", ",", "256", "-1", "a", "1.5", "0x10", "1 2", "12 ,3\n", "1__0", "_1", "1_", "99999999999999999999999"]
w("    static let byteLists: [PCByteListVector] = [")
for c in bl:
    try: r = hx(_enBytes(c))
    except ValueError: r = None
    w('        PCByteListVector(input: %s, expectedHex: %s),' % (swift_str(c), opt(r)))
w("    ]")

# ---- Flux de connexion (clients.py + _Communication.after_auth réels)
w("    static let logins: [PCLoginVector] = [")
def login_vec(name, username, password, alea, ivtemp, challenge, ent, cle_plain):
    sha_up = SHA256.new((password if ent else alea + password).encode()).hexdigest().upper()
    e = _Encryption()
    e.aes_set_iv(MD5.new(ivtemp).digest())          # self.communication.encryption.aes_iv après initialise()
    iv = e.aes_iv
    if ent: e.aes_set_key(sha_up.encode())
    else:   e.aes_set_key((username + sha_up).encode())
    auth_key = e.aes_key
    ch = e.aes_encrypt(challenge.encode()).hex()
    # serveur : chiffre `cle` avec auth_key + iv
    cle_ct = e.aes_encrypt(cle_plain.encode()).hex()
    comm = object.__new__(_Communication)
    comm.encryption = _Encryption(); comm.encryption.aes_iv = iv
    comm.cookies = {"c": "1"}
    comm.after_auth({"dataSec": {"data": {"cle": cle_ct}}}, auth_key)
    final = comm.encryption.aes_key
    w('        PCLoginVector(name: %s, username: %s, password: %s, alea: %s, ivTempHex: "%s", challenge: %s, ent: %s, sha256UpperHex: "%s", authKeyHex: "%s", ivHex: "%s", challengeCipherHex: "%s", cle: %s, cleCipherHex: "%s", finalKeyHex: "%s"),' % (
        swift_str(name), swift_str(username), swift_str(password), swift_str(alea), hx(ivtemp), swift_str(challenge), 'true' if ent else 'false',
        sha_up, hx(auth_key), hx(iv), ch, swift_str(cle_plain), cle_ct, hx(final)))
ivt = bytes.fromhex("a1b2c3d4e5f60718293a4b5c6d7e8f90")
login_vec("standard", "eleve.test", "P@ssw0rd é", "xYz9", ivt, "Zq3Rk1Lm0pX8aB", False, "12,200,0,255,7,99,128,1,64,32,16,8,4,2,100,250")
login_vec("sans alea", "Jean", "secret", "", ivt, "challenge-xyz", False, "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16")
login_vec("ENT", "ignoré", "mdp-ent", "ignoré", ivt, "ChAlLeNgE", True, "250,251,252,253,0,1,2,3,10,20,30,40,50,60,70,80")
w("    ]")

# ---- RSA
e = _Encryption()
n, ex = e.RSA_1024_MODULO, e.RSA_1024_EXPONENT
key = RSA.construct((n, ex))
w('    static let rsaModulusHex = "%s"' % ("%0256x" % n))
w('    static let rsaExponent = %d' % ex)
w('    static let rsaPublicKeyDERHex = "%s"  // RSA.construct(...).export_key("DER", pkcs=1)' % hx(key.export_key(format="DER", pkcs=1)))
w("    static let rsa: [PCRSAVector] = [")
# NB: le chiffrement RSA PKCS#1 v1.5 est aléatoire (PS). On injecte donc un randfunc déterministe dans le MÊME code
# pycryptodome (PKCS1_v1_5.encrypt) pour obtenir un chiffré reproductible : c = (00 02 PS 00 M)^e mod n.
from Crypto.Cipher import PKCS1_v1_5
class DetRand:
    def __init__(self, seed): self.i = seed
    def __call__(self, n):
        out = bytearray()
        for _ in range(n):
            self.i = (self.i * 31 + 7) % 256
            out.append(self.i)       # peut valoir 0 : pycryptodome le rejette et retire un octet
        return bytes(out)
def rsa_vec(name, msg, seed):
    r = DetRand(seed)
    k = 128
    ct = PKCS1_v1_5.new(key, randfunc=r).encrypt(msg)
    # reconstitue PS exactement comme pycryptodome (octets non nuls consécutifs du flux)
    r2 = DetRand(seed); ps = bytearray()
    while len(ps) != k - len(msg) - 3:
        bte = r2(1)[0]
        if bte != 0: ps.append(bte)
    em = b"\x00\x02" + bytes(ps) + b"\x00" + msg
    assert len(em) == 128 and pow(int.from_bytes(em,"big"), ex, n) == int.from_bytes(ct,"big") and len(ct) == 128
    w('        PCRSAVector(name: "%s", messageHex: "%s", paddingHex: "%s", ciphertextHex: "%s"),' % (name, hx(msg), hx(bytes(ps)), hx(ct)))
rsa_vec("iv_temp 16 octets", bytes.fromhex("a1b2c3d4e5f60718293a4b5c6d7e8f90"), 11)
rsa_vec("vide", b"", 5)
rsa_vec("1 octet", b"\x00", 99)
rsa_vec("117 octets (max)", bytes((i*5+1)&0xff for i in range(117)), 200)
w("    ]")
assert len(e.rsa_encrypt(bytes(16))) == 128
try:
    e.rsa_encrypt(bytes(118)); raise SystemExit("118 octets aurait dû échouer")
except ValueError: pass
w("    static let rsaMaxMessageLength = 117  // pycryptodome: ValueError au-delà de k-11")
w("}")
print("\n".join(out))
