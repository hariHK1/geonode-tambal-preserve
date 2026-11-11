#!/usr/bin/env python3
"""Bangkitkan urutan-gmd.xsl: urutan elemen anak tiap kelas ISO 19139 (gmd), dibaca dari XSD resmi ISO/TC 211.

    python buat_urutan_gmd.py FOLDER_XSD_GMD   # folder berisi gmd.xsd dkk. (schemas.isotc211.org/19139/-/gmd/1.0)

Hasilnya dipakai geomdb-ke-mdb.xsl untuk menyusun ulang elemen yang urutannya salah (mis. XML plugin GeoMDB
1.0.5) sebelum dikonversi; tanpa itu XSLT GeoNetwork menyalin urutan yang salah ke hasil ISO 19115-3.
Tidak dijalankan saat menambal; jalankan ulang hanya bila ingin membangkitkan ulang urutan-gmd.xsl.
"""
import glob
import os
import sys

from lxml import etree

XS = "{http://www.w3.org/2001/XMLSchema}"


def baca(folder):
    tipe, elemen = {}, {}
    for f in sorted(glob.glob(os.path.join(folder, "*.xsd"))):
        akar = etree.parse(f).getroot()
        for el in akar.findall(XS + "element"):
            if el.get("type", "").startswith("gmd:"):
                elemen[el.get("name")] = el.get("type")[4:]
        for ct in akar.findall(XS + "complexType"):
            ext = ct.find("%scomplexContent/%sextension" % (XS, XS))
            if ext is None:
                continue
            seq = ext.find(XS + "sequence")
            anak = [e.get("name") for e in (seq.findall(XS + "element") if seq is not None else [])]
            basis = ext.get("base")
            tipe[ct.get("name")] = (basis[4:] if basis.startswith("gmd:") else None, anak)
    return tipe, elemen


def urutan(tipe, nama):
    basis, anak = tipe[nama]
    return (urutan(tipe, basis) if basis in tipe else []) + anak


def main(folder):
    tipe, elemen = baca(folder)
    baris = []
    for nama in sorted(elemen):
        u = urutan(tipe, elemen[nama]) if elemen[nama] in tipe else []
        if len(u) > 1:  # satu anak / pilihan (xs:choice) tidak perlu diurutkan
            baris.append('    <u k="%s">%s</u>' % (nama, " ".join(u)))
    keluar = os.path.join(os.path.dirname(os.path.abspath(__file__)), "urutan-gmd.xsl")
    with open(keluar, "w", encoding="utf-8", newline="\n") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                 "<!-- DIBANGKITKAN oleh buat_urutan_gmd.py dari XSD ISO 19139 (gmd 1.0); jangan disunting manual.\n"
                 "     Urutan elemen anak tiap kelas gmd (termasuk elemen kelas induknya). -->\n"
                 '<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"\n'
                 '                xmlns:g="urn:geomdb" exclude-result-prefixes="#all">\n'
                 '  <xsl:variable name="g:urutan-gmd" as="element()*">\n'
                 + "\n".join(baris) +
                 "\n  </xsl:variable>\n</xsl:stylesheet>\n")
    print("%d kelas -> %s" % (len(baris), keluar))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
