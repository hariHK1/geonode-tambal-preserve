<?xml version="1.0" encoding="UTF-8"?>
<!--
  GeoMDB: ISO 19139 (gmd) -> ISO 19115-3:2018 (mdb 2.0), seperti GeoNetwork.

  Konversinya sendiri adalah XSLT GeoNetwork di ISO19139/ (lihat SUMBER.md), tidak diubah. Berkas ini
  membungkusnya dalam tiga tahap:

  A. Sebelum konversi, XML gmd dirapikan; tanpa ini XSLT GeoNetwork menyalin kesalahannya ke ISO 19115-3:
     - elemen disusun ulang mengikuti urutan XSD ISO 19139 (urutan-gmd.xsl); elemen yang tidak dikenal tetap
       menempel di belakang elemen yang semula mendahuluinya. Contoh: ekspor plugin GeoMDB 1.0.5.
     - laporan kualitas (gmd:report) yang propertinya dibungkus berlapis, mis. gmd:measureDescription di dalam
       gmd:measureDescription (plugin GeoMDB 1.0.5), diratakan menjadi properti langsung DQ_Element.

  Versi namespace: ISO 19115-3:2018, yaitu yang diimpor XSD resmi mds/2.0 (mdb, mds, cit, mrl, mrc, mac, mda, msr,
  srv = 2.0; mri, mcc, gco, gex, lan, mrd, mco, mmi, mex, mrs, mpc, mas = 1.0; mdq 19157-2 = 1.0). Inilah juga
  outputSchema profil iso19115p3 pycsw (http://standards.iso.org/iso/19115/-3/mdb/2.0).

  B. Konversi GeoNetwork, dengan empat penggantian:
     - associatedResource ditulis lengkap dengan nama sumber daya (bawaan GeoNetwork hanya uuidref, sehingga
       judul seri/dataset terkait hilang);
     - gmd:updateScope -> mmi:maintenanceScope: template GeoNetwork untuk ini memakai nama mode yang salah
       ("from19139to19115-3", tanpa ".2018"), jadi tidak pernah terpanggil dan elemennya tersalin mentah;
     - deklarasi namespace di elemen akar: GeoNetwork menulis mda/1.0, padahal set 2018 memakai mda/2.0;
     - gmd:locale berbahasa sama dengan bahasa metadata cocok dengan dua template GeoNetwork sekaligus
       (peringatan "ambiguous rule match"); di sini ditetapkan satu: dibuang, seperti maksud GeoNetwork.

  C. Sesudah konversi, hasilnya dirapikan supaya lolos XSD + Schematron ISO 19115-3:
     1. dateInfo "creation" (wajib di ISO 19115-1) ditambahkan bila belum ada: dari parameter
        tanggal-dibuat (tanggal resource dibuat di GeoNode), atau tanggal dateStamp.
     2. cit:date dan cit:editionDate wajib gco:DateTime di skema 2018: gco:Date diubah.
     3. CI_Organisation tanpa nama dan logo yang hanya membungkus satu CI_Individual menjadi CI_Individual
        (GeoNode menulis gmd:organisationName kosong untuk pengguna tanpa organisasi).
     4. Kode peran berupa label GeoNode ("Metadata Author", "Point of Contact", ...) menjadi kode CI_RoleCode ISO.
     5. Bahasa sumber daya: GeoNetwork menulis bahasa yang berbeda dari bahasa metadata sebagai otherLocale;
        bila defaultLocale tidak ada, otherLocale pertama menjadi defaultLocale.
     6. Elemen ekstensi bertipe codelist/enumeration wajib punya conceptName dan code: diisi dari name,
        dan untuk code dari gmd:shortName / gmd:domainCode bila ada (keduanya dibuang GeoNetwork).
     7. lan:PT_Locale tanpa characterEncoding diberi utf8 (encoding dokumen ini).
     8. DQ_ConformanceResult tanpa specification / explanation / pass: elemen wajib itu ditulis kosong dengan
        gco:nilReason (missing / unknown) supaya jelas datanya tidak ada, bukan dikarang.
     9. mrl:scope berisi mrl:level langsung (plugin GeoMDB 1.0.5 menulis gmd:scope/gmd:level di LI_Lineage dan
        LI_Source) dibungkus mcc:MD_Scope.
    10. CI_Individual di dalam organisasi tanpa nama, jabatan, maupun kontak (mis. gmd:individualName yang hanya
        ber-nilReason) dibuang: organisasinya sudah mewakili pihak itu.
    11. gmd:dataSetURI menjadi identifier sitasi sumber daya. GeoNetwork hanya menuliskannya bila sitasi punya
        citedResponsibleParty; tanpa itu nilainya hilang.
    12. xsi:schemaLocation ke XSD resmi mdb 2.0 ditambahkan bila belum ada.
    13. Hasil kualitas ganda dibuang: template DQ GeoNetwork menerapkan gmd:result dua kali bila metode evaluasi
        terisi (ISO19139/mapping/DQ.xsl), sehingga setiap mdq:result tertulis dua kali.
    14. gco:LocalName (ada di gco 19139, tidak ada di gco 19115-3) menjadi gco:ScopedName, mis. featureTypeName.

  Yang sengaja TIDAK diubah: pihak tanpa nama individu, organisasi, maupun jabatan (GeoNode menulisnya untuk akun
  yang profilnya belum diisi) dibuang GeoNetwork karena ISO 19115-3 mewajibkan nama; lengkapi profil akunnya.
-->
<xsl:stylesheet version="2.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:gmd="http://www.isotc211.org/2005/gmd"
                xmlns:mdb="http://standards.iso.org/iso/19115/-3/mdb/2.0"
                xmlns:cit="http://standards.iso.org/iso/19115/-3/cit/2.0"
                xmlns:mri="http://standards.iso.org/iso/19115/-3/mri/1.0"
                xmlns:mex="http://standards.iso.org/iso/19115/-3/mex/1.0"
                xmlns:lan="http://standards.iso.org/iso/19115/-3/lan/1.0"
                xmlns:mdq="http://standards.iso.org/iso/19157/-2/mdq/1.0"
                xmlns:mrl="http://standards.iso.org/iso/19115/-3/mrl/2.0"
                xmlns:mcc="http://standards.iso.org/iso/19115/-3/mcc/1.0"
                xmlns:mmi="http://standards.iso.org/iso/19115/-3/mmi/1.0"
                xmlns:gco="http://standards.iso.org/iso/19115/-3/gco/1.0"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:g="urn:geomdb"
                exclude-result-prefixes="#all">

  <xsl:import href="ISO19139/fromISO19139.xsl"/>
  <xsl:include href="urutan-gmd.xsl"/>

  <xsl:param name="tanggal-dibuat" select="''"/>

  <!-- B. menggantikan variabel bernama sama di ISO19139/mapping/core.xsl (presedensi impor lebih tinggi) -->
  <xsl:variable name="associatedResourceAsMetadataReferenceOnly" select="false()"/>

  <!-- B. sama dengan template GeoNetwork di ISO19139/mapping/core.xsl, dengan nama mode yang benar -->
  <xsl:template match="gmd:updateScope" priority="5" mode="from19139to19115-3.2018">
    <mmi:maintenanceScope>
      <mcc:MD_Scope>
        <xsl:call-template name="writeCodelistElement">
          <xsl:with-param name="elementName" select="'mcc:level'"/>
          <xsl:with-param name="codeListName" select="'mcc:MD_ScopeCode'"/>
          <xsl:with-param name="codeListValue" select="gmd:MD_ScopeCode/@codeListValue"/>
        </xsl:call-template>
      </mcc:MD_Scope>
    </mmi:maintenanceScope>
  </xsl:template>

  <!-- B. menggantikan template bernama sama di ISO19139/utility/create19115-3Namespaces.xsl: mda 2.0 -->
  <xsl:template name="add-iso19115-3.2018-namespaces">
    <xsl:namespace name="xsi" select="'http://www.w3.org/2001/XMLSchema-instance'"/>
    <xsl:namespace name="cat" select="'http://standards.iso.org/iso/19115/-3/cat/1.0'"/>
    <xsl:namespace name="gfc" select="'http://standards.iso.org/iso/19110/gfc/1.1'"/>
    <xsl:namespace name="cit" select="'http://standards.iso.org/iso/19115/-3/cit/2.0'"/>
    <xsl:namespace name="gcx" select="'http://standards.iso.org/iso/19115/-3/gcx/1.0'"/>
    <xsl:namespace name="gex" select="'http://standards.iso.org/iso/19115/-3/gex/1.0'"/>
    <xsl:namespace name="lan" select="'http://standards.iso.org/iso/19115/-3/lan/1.0'"/>
    <xsl:namespace name="srv" select="'http://standards.iso.org/iso/19115/-3/srv/2.0'"/>
    <xsl:namespace name="mas" select="'http://standards.iso.org/iso/19115/-3/mas/1.0'"/>
    <xsl:namespace name="mcc" select="'http://standards.iso.org/iso/19115/-3/mcc/1.0'"/>
    <xsl:namespace name="mco" select="'http://standards.iso.org/iso/19115/-3/mco/1.0'"/>
    <xsl:namespace name="mda" select="'http://standards.iso.org/iso/19115/-3/mda/2.0'"/>
    <xsl:namespace name="mdb" select="'http://standards.iso.org/iso/19115/-3/mdb/2.0'"/>
    <xsl:namespace name="mds" select="'http://standards.iso.org/iso/19115/-3/mds/2.0'"/>
    <xsl:namespace name="mdt" select="'http://standards.iso.org/iso/19115/-3/mdt/2.0'"/>
    <xsl:namespace name="mex" select="'http://standards.iso.org/iso/19115/-3/mex/1.0'"/>
    <xsl:namespace name="mmi" select="'http://standards.iso.org/iso/19115/-3/mmi/1.0'"/>
    <xsl:namespace name="mpc" select="'http://standards.iso.org/iso/19115/-3/mpc/1.0'"/>
    <xsl:namespace name="mrc" select="'http://standards.iso.org/iso/19115/-3/mrc/2.0'"/>
    <xsl:namespace name="mrd" select="'http://standards.iso.org/iso/19115/-3/mrd/1.0'"/>
    <xsl:namespace name="mri" select="'http://standards.iso.org/iso/19115/-3/mri/1.0'"/>
    <xsl:namespace name="mrl" select="'http://standards.iso.org/iso/19115/-3/mrl/2.0'"/>
    <xsl:namespace name="mrs" select="'http://standards.iso.org/iso/19115/-3/mrs/1.0'"/>
    <xsl:namespace name="msr" select="'http://standards.iso.org/iso/19115/-3/msr/2.0'"/>
    <xsl:namespace name="mdq" select="'http://standards.iso.org/iso/19157/-2/mdq/1.0'"/>
    <xsl:namespace name="dqm" select="'http://standards.iso.org/iso/19157/-2/dqm/1.0'"/>
    <xsl:namespace name="mac" select="'http://standards.iso.org/iso/19115/-3/mac/2.0'"/>
    <xsl:namespace name="gco" select="'http://standards.iso.org/iso/19115/-3/gco/1.0'"/>
    <xsl:namespace name="gml" select="'http://www.opengis.net/gml/3.2'"/>
    <xsl:namespace name="xlink" select="'http://www.w3.org/1999/xlink'"/>
  </xsl:template>

  <!-- B. locale berbahasa sama dengan bahasa metadata: satu aturan pasti (GeoNetwork core.xsl punya dua yang cocok) -->
  <xsl:template match="gmd:locale[*/gmd:languageCode/*/@codeListValue = $mainLanguage]" priority="5"
                mode="from19139to19115-3.2018"/>

  <xsl:variable name="daftar-kode"
                select="'https://standards.iso.org/iso/19115/resources/Codelists/cat/codelists.xml'"/>

  <!-- label peran GeoNode (geonode/people/__init__.py) -> CI_RoleCode -->
  <xsl:variable name="peran" as="element()*">
    <p label="Owner" kode="owner"/>
    <p label="Metadata Author" kode="author"/>
    <p label="Processor" kode="processor"/>
    <p label="Publisher" kode="publisher"/>
    <p label="Custodian" kode="custodian"/>
    <p label="Point of Contact" kode="pointOfContact"/>
    <p label="Distributor" kode="distributor"/>
    <p label="Resource User" kode="user"/>
    <p label="Resource Provider" kode="resourceProvider"/>
    <p label="Originator" kode="originator"/>
    <p label="Principal Investigator" kode="principalInvestigator"/>
  </xsl:variable>

  <!-- A. sumber gmd yang urutannya sudah dirapikan -->
  <xsl:variable name="g:gmd">
    <xsl:apply-templates select="/" mode="urut-gmd"/>
  </xsl:variable>

  <xsl:template match="/" priority="100">
    <xsl:variable name="mdb">
      <xsl:for-each select="$g:gmd">
        <xsl:call-template name="to-iso19115-3"/>
      </xsl:for-each>
    </xsl:variable>
    <xsl:apply-templates select="$mdb" mode="geomdb"/>
  </xsl:template>

  <!-- ── A. susun ulang anak elemen gmd menurut XSD ───────────────────────────────────────────────────── -->

  <xsl:template match="@*|node()" mode="urut-gmd">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()" mode="urut-gmd"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="gmd:*[local-name() = $g:urutan-gmd/@k]" mode="urut-gmd">
    <xsl:variable name="urutan" select="tokenize($g:urutan-gmd[@k = local-name(current())], ' ')"/>
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="urut-gmd"/>
      <!-- xsl:sort stabil; elemen tak dikenal ikut di belakang elemen dikenal terdekat yang mendahuluinya -->
      <xsl:apply-templates select="*" mode="urut-gmd">
        <xsl:sort select="g:posisi(., $urutan)" data-type="number"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

  <xsl:function name="g:posisi" as="xs:double">
    <xsl:param name="el" as="element()"/>
    <xsl:param name="urutan" as="xs:string*"/>
    <xsl:variable name="i" select="g:indeks($el, $urutan)"/>
    <xsl:sequence select="if (exists($i)) then $i
                          else (for $p in ($el/preceding-sibling::*[exists(g:indeks(., $urutan))])[last()]
                                return g:indeks($p, $urutan), 0)[1] + 0.5"/>
  </xsl:function>

  <xsl:function name="g:indeks" as="xs:integer?">
    <xsl:param name="el" as="element()"/>
    <xsl:param name="urutan" as="xs:string*"/>
    <xsl:sequence select="if (namespace-uri($el) = 'http://www.isotc211.org/2005/gmd')
                          then index-of($urutan, local-name($el))[1] else ()"/>
  </xsl:function>

  <!-- properti DQ_Element yang dibungkus berlapis: turun sampai properti terdalam (daun) -->
  <xsl:variable name="g:properti-dq" select="tokenize($g:urutan-gmd[@k = 'DQ_DomainConsistency'], ' ')"/>

  <xsl:template match="gmd:report/gmd:*[*/*[local-name() = $g:properti-dq
                                           and namespace-uri() = 'http://www.isotc211.org/2005/gmd']]"
                mode="urut-gmd" priority="5">
    <xsl:variable name="daun" as="element()*">
      <xsl:apply-templates select="*" mode="dq-daun"/>
    </xsl:variable>
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="urut-gmd"/>
      <xsl:for-each select="$daun">
        <xsl:sort select="(index-of($g:properti-dq, local-name()), 9999)[1]" data-type="number"/>
        <xsl:sequence select="."/>
      </xsl:for-each>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="*" mode="dq-daun">
    <xsl:choose>
      <xsl:when test="local-name() = $g:properti-dq and namespace-uri() = 'http://www.isotc211.org/2005/gmd'
                      and *[local-name() = $g:properti-dq and namespace-uri() = 'http://www.isotc211.org/2005/gmd']">
        <xsl:apply-templates select="*" mode="dq-daun"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:apply-templates select="." mode="urut-gmd"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ── C. rapikan hasil konversi ────────────────────────────────────────────────────────────────────── -->

  <xsl:template match="@*|node()" mode="geomdb">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()" mode="geomdb"/>
    </xsl:copy>
  </xsl:template>

  <!-- 1. dateInfo creation: sebelum dateInfo pertama, atau sesudah contact terakhir bila dateInfo tidak ada -->
  <xsl:template match="mdb:MD_Metadata" mode="geomdb">
    <xsl:variable name="perlu" as="xs:boolean"
                  select="not(mdb:dateInfo/cit:CI_Date/cit:dateType/cit:CI_DateTypeCode/@codeListValue = 'creation')"/>
    <xsl:variable name="tanggal" select="if (normalize-space($tanggal-dibuat)) then normalize-space($tanggal-dibuat)
                                         else normalize-space((mdb:dateInfo/cit:CI_Date/cit:date/*)[1])"/>
    <xsl:variable name="ada-dateinfo" select="exists(mdb:dateInfo)"/>
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="geomdb"/>
      <xsl:if test="not(@xsi:schemaLocation)" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <xsl:attribute name="xsi:schemaLocation"
                       select="'http://standards.iso.org/iso/19115/-3/mdb/2.0 https://schemas.isotc211.org/19115/-3/mdb/2.0/mdb.xsd'"/>
      </xsl:if>
      <xsl:for-each select="node()">
        <xsl:if test="$perlu and $tanggal and self::mdb:dateInfo and not(preceding-sibling::mdb:dateInfo)">
          <xsl:call-template name="tanggal-dibuat">
            <xsl:with-param name="tanggal" select="$tanggal"/>
          </xsl:call-template>
        </xsl:if>
        <xsl:apply-templates select="." mode="geomdb"/>
        <xsl:if test="$perlu and $tanggal and not($ada-dateinfo) and self::mdb:contact
                      and not(following-sibling::mdb:contact)">
          <xsl:call-template name="tanggal-dibuat">
            <xsl:with-param name="tanggal" select="$tanggal"/>
          </xsl:call-template>
        </xsl:if>
      </xsl:for-each>
    </xsl:copy>
  </xsl:template>

  <xsl:template name="tanggal-dibuat">
    <xsl:param name="tanggal"/>
    <mdb:dateInfo>
      <cit:CI_Date>
        <cit:date>
          <gco:DateTime>
            <xsl:value-of select="g:jadi-datetime($tanggal)"/>
          </gco:DateTime>
        </cit:date>
        <cit:dateType>
          <cit:CI_DateTypeCode codeList="{$daftar-kode}#CI_DateTypeCode" codeListValue="creation">creation</cit:CI_DateTypeCode>
        </cit:dateType>
      </cit:CI_Date>
    </mdb:dateInfo>
  </xsl:template>

  <!-- 2. gco:Date -> gco:DateTime -->
  <xsl:template match="cit:date/gco:Date | cit:editionDate/gco:Date" mode="geomdb">
    <gco:DateTime>
      <xsl:value-of select="g:jadi-datetime(.)"/>
    </gco:DateTime>
  </xsl:template>

  <xsl:function name="g:jadi-datetime" as="xs:string">
    <xsl:param name="nilai"/>
    <xsl:variable name="t" select="normalize-space($nilai)"/>
    <xsl:sequence select="if (matches($t, '^\d{4}$')) then concat($t, '-01-01T00:00:00')
                          else if (matches($t, '^\d{4}-\d{2}$')) then concat($t, '-01T00:00:00')
                          else if (matches($t, '^\d{4}-\d{2}-\d{2}(Z|[+-]\d{2}:\d{2})?$'))
                               then concat(substring($t, 1, 10), 'T00:00:00', substring($t, 11))
                          else $t"/>
  </xsl:function>

  <!-- 3. organisasi kosong pembungkus satu orang -> CI_Individual (urutan CI_Party lalu positionName) -->
  <xsl:template match="cit:party/cit:CI_Organisation[not(normalize-space(cit:name)) and not(cit:logo)
                       and count(cit:individual/cit:CI_Individual) = 1]" mode="geomdb">
    <xsl:variable name="orang" select="cit:individual/cit:CI_Individual"/>
    <cit:CI_Individual>
      <xsl:apply-templates select="$orang/cit:name" mode="geomdb"/>
      <xsl:apply-templates select="cit:contactInfo, $orang/cit:contactInfo" mode="geomdb"/>
      <xsl:apply-templates select="cit:partyIdentifier, $orang/cit:partyIdentifier" mode="geomdb"/>
      <xsl:apply-templates select="$orang/cit:positionName" mode="geomdb"/>
    </cit:CI_Individual>
  </xsl:template>

  <!-- 4. label peran GeoNode -> kode ISO -->
  <xsl:template match="cit:CI_RoleCode[normalize-space(@codeListValue) = $peran/@label]" mode="geomdb">
    <xsl:variable name="kode" select="($peran[@label = normalize-space(current()/@codeListValue)]/@kode)[1]"/>
    <cit:CI_RoleCode codeList="{$daftar-kode}#CI_RoleCode" codeListValue="{$kode}">
      <xsl:value-of select="$kode"/>
    </cit:CI_RoleCode>
  </xsl:template>

  <!-- 5. bahasa sumber daya (defaultLocale tepat mendahului otherLocale di XSD, jadi cukup ganti nama) -->
  <xsl:template match="mri:MD_DataIdentification[not(mri:defaultLocale)]/mri:otherLocale[1]" mode="geomdb">
    <mri:defaultLocale>
      <xsl:apply-templates select="@*|node()" mode="geomdb"/>
    </mri:defaultLocale>
  </xsl:template>

  <!-- 6. conceptName + code elemen ekstensi codelist (keduanya di akhir urutan XSD mex) -->
  <xsl:template match="mex:MD_ExtendedElementInformation[
                         mex:dataType/*/@codeListValue = ('codelist', 'enumeration', 'codelistElement')]" mode="geomdb">
    <xsl:variable name="nama" select="normalize-space(mex:name)"/>
    <xsl:variable name="asal"
                  select="($g:gmd//gmd:MD_ExtendedElementInformation)[count(current()/preceding::mex:MD_ExtendedElementInformation) + 1]"/>
    <xsl:variable name="kode"
                  select="(normalize-space($asal[normalize-space(gmd:name) = $nama]/gmd:shortName),
                           normalize-space($asal[normalize-space(gmd:name) = $nama]/gmd:domainCode), $nama)[. != ''][1]"/>
    <xsl:copy>
      <xsl:apply-templates select="@*, node() except mex:code" mode="geomdb"/>
      <xsl:if test="not(mex:conceptName) and $nama">
        <mex:conceptName>
          <gco:CharacterString><xsl:value-of select="$nama"/></gco:CharacterString>
        </mex:conceptName>
      </xsl:if>
      <xsl:choose>
        <xsl:when test="normalize-space(mex:code)">
          <xsl:apply-templates select="mex:code" mode="geomdb"/>
        </xsl:when>
        <xsl:when test="$kode">
          <mex:code>
            <gco:CharacterString><xsl:value-of select="$kode"/></gco:CharacterString>
          </mex:code>
        </xsl:when>
      </xsl:choose>
    </xsl:copy>
  </xsl:template>

  <!-- 7. PT_Locale wajib characterEncoding (urutan: language, country, characterEncoding) -->
  <xsl:template match="lan:PT_Locale[not(lan:characterEncoding)]" mode="geomdb">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()" mode="geomdb"/>
      <lan:characterEncoding>
        <lan:MD_CharacterSetCode codeList="{$daftar-kode}#MD_CharacterSetCode" codeListValue="utf8">utf8</lan:MD_CharacterSetCode>
      </lan:characterEncoding>
    </xsl:copy>
  </xsl:template>

  <!-- 8. elemen wajib DQ_ConformanceResult (urutan: resultScope, dateTime, specification, explanation, pass) -->
  <xsl:template match="mdq:DQ_ConformanceResult[not(mdq:specification and mdq:explanation and mdq:pass)]" mode="geomdb">
    <xsl:copy>
      <xsl:apply-templates select="@*, mdq:resultScope, mdq:dateTime" mode="geomdb"/>
      <xsl:apply-templates select="mdq:specification" mode="geomdb"/>
      <xsl:if test="not(mdq:specification)"><mdq:specification gco:nilReason="missing"/></xsl:if>
      <xsl:apply-templates select="mdq:explanation" mode="geomdb"/>
      <xsl:if test="not(mdq:explanation)"><mdq:explanation gco:nilReason="missing"/></xsl:if>
      <xsl:apply-templates select="mdq:pass" mode="geomdb"/>
      <xsl:if test="not(mdq:pass)"><mdq:pass gco:nilReason="unknown"/></xsl:if>
      <xsl:apply-templates select="* except (mdq:resultScope, mdq:dateTime, mdq:specification, mdq:explanation, mdq:pass)"
                           mode="geomdb"/>
    </xsl:copy>
  </xsl:template>

  <!-- 11. dataSetURI -> identifier sitasi (urutan cit: title, alternateTitle, date, edition, editionDate, identifier, ...) -->
  <xsl:variable name="g:uri-dataset" select="normalize-space(($g:gmd/*/gmd:dataSetURI)[1])"/>

  <xsl:template match="mdb:identificationInfo[1]/*/mri:citation/cit:CI_Citation[$g:uri-dataset != ''
                       and not(cit:identifier/*/mcc:code[normalize-space() = $g:uri-dataset])]" mode="geomdb">
    <xsl:variable name="sebelum" select="cit:title | cit:alternateTitle | cit:date | cit:edition | cit:editionDate | cit:identifier"/>
    <xsl:copy>
      <xsl:apply-templates select="@*, $sebelum" mode="geomdb"/>
      <cit:identifier>
        <mcc:MD_Identifier>
          <mcc:code>
            <gco:CharacterString><xsl:value-of select="$g:uri-dataset"/></gco:CharacterString>
          </mcc:code>
        </mcc:MD_Identifier>
      </cit:identifier>
      <xsl:apply-templates select="* except $sebelum" mode="geomdb"/>
    </xsl:copy>
  </xsl:template>

  <!-- 13. hasil ganda dari DQ.xsl: paruh kedua daftar mdq:result sama persis dengan paruh pertama -->
  <xsl:template match="mdq:report/*[mdq:result and count(mdq:result) mod 2 = 0]" mode="geomdb">
    <xsl:variable name="hasil" select="mdq:result"/>
    <xsl:variable name="n" select="count($hasil) idiv 2"/>
    <xsl:variable name="ganda" select="every $i in 1 to $n satisfies deep-equal($hasil[$i], $hasil[$i + $n])"/>
    <xsl:copy>
      <xsl:apply-templates select="@*, node()[not($ganda and exists(. intersect $hasil[position() gt $n]))]"
                           mode="geomdb"/>
    </xsl:copy>
  </xsl:template>

  <!-- 14. LocalName -> ScopedName -->
  <xsl:template match="gco:LocalName" mode="geomdb">
    <gco:ScopedName>
      <xsl:apply-templates select="@*|node()" mode="geomdb"/>
    </gco:ScopedName>
  </xsl:template>

  <!-- 9. scope tanpa MD_Scope -->
  <xsl:template match="mrl:scope[mrl:level and not(mcc:MD_Scope)]" mode="geomdb">
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="geomdb"/>
      <mcc:MD_Scope>
        <mcc:level>
          <xsl:apply-templates select="mrl:level/(@*|node())" mode="geomdb"/>
        </mcc:level>
      </mcc:MD_Scope>
    </xsl:copy>
  </xsl:template>

  <!-- 10. individu kosong di dalam organisasi -->
  <xsl:template match="cit:CI_Organisation/cit:individual[cit:CI_Individual[not(normalize-space(cit:name))
                       and not(normalize-space(cit:positionName)) and not(cit:contactInfo) and not(cit:partyIdentifier)]]"
                mode="geomdb"/>

</xsl:stylesheet>
