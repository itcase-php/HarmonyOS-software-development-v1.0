"""Actual native execution plus independent PDF/pixel checks. No device results."""
import argparse, json, subprocess, zipfile, struct, zlib
from pathlib import Path
from PIL import Image, ImageChops, ImageCms
from pypdf import PdfReader

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(); parser.add_argument('cli',type=Path); args=parser.parse_args()
directory=root/'tmp/pdfs/core-engines';directory.mkdir(parents=True,exist_ok=True)
poppler=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin/pdftoppm.exe'
cases=[]
def call(format,path,expected=0):
    output=directory/(path.stem+'.pdf')
    command=[str(args.cli.resolve()),format,str(path)]
    if format not in ['docx','pptx']:command.append(str(output))
    result=subprocess.run(command,capture_output=True,text=True)
    assert result.returncode==expected,(path.name,result.returncode,result.stderr)
    cases.append({'name':path.name,'expectedExit':expected,'passed':True})
    return output
source=Image.new('RGBA',(80,60))
for y in range(60):
    for x in range(80):source.putpixel((x,y),(x*3,y*4,100,(x+y)*255//138))
for mode in ['RGBA','RGB','L','LA','P','1']:
    image=source.convert(mode);path=directory/(mode+'.png');image.save(path)
    output=call('png',path);pdf=PdfReader(output,strict=True);assert len(pdf.pages)==1
    page=pdf.pages[0];assert list(page.mediabox)==[0,0,60,45]
    xobject=page['/Resources']['/XObject']['/Im0'].get_object()
    rgba=Image.open(path).convert('RGBA');rgb=rgba.convert('RGB');assert xobject.get_data()==rgb.tobytes()
    alpha=rgba.getchannel('A')
    if alpha.getextrema()!=(255,255):assert xobject['/SMask'].get_object().get_data()==alpha.tobytes()
    else:assert '/SMask' not in xobject
    prefix=directory/(mode+'-render')
    subprocess.run([str(poppler),'-r','960','-singlefile','-png',str(output),str(prefix)],check=True,capture_output=True)
    rendered=Image.open(str(prefix)+'.png').convert('RGB').resize(rgba.size, Image.Resampling.NEAREST);background=Image.new('RGBA',rgba.size,'white');background.alpha_composite(rgba)
    difference=ImageChops.difference(rendered,background.convert('RGB'))
    assert max(difference.getextrema(),key=lambda p:p[1])[1]<=2,(mode,difference.getextrema())
jpeg_output=call('jpeg',root/'entry/src/main/cpp/tests/fixtures/baseline.jpg')
assert len(PdfReader(jpeg_output,strict=True).pages)==1
bad_save=subprocess.run([str(args.cli.resolve()),'png',str(directory/'RGB.png'),str(directory)],capture_output=True,text=True)
assert bad_save.returncode!=0 and 'CLI_OUTPUT_OPEN' in bad_save.stderr
cases.append({'name':'output directory cannot be reported as a saved PDF','passed':True})
corrupted=directory/'crc.png';data=bytearray((directory/'RGB.png').read_bytes());data[29]^=1;corrupted.write_bytes(data);call('png',corrupted,5)
truncated=directory/'truncated.png';truncated.write_bytes((directory/'RGB.png').read_bytes()[:-10]);call('png',truncated,5)
profile=directory/'icc.png';source.save(profile,icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes());call('png',profile,17)
sixteen=directory/'16bit.png';Image.new('I;16',(80,60),12345).save(sixteen);call('png',sixteen,17)
animated=directory/'animated.png';source.save(animated,save_all=True,append_images=[source]);call('png',animated,17)
for dpi in [(300,300),(300,150)]:
    path=directory/('density-'+str(dpi[1])+'.png');source.save(path,dpi=dpi)
    stored=Image.open(path).info['dpi']  # pHYs stores integer pixels/metre, not exact requested DPI.
    pdf=PdfReader(call('png',path),strict=True);box=pdf.pages[0].mediabox
    assert abs(float(box.width)-80*72/stored[0])<0.000002
    assert abs(float(box.height)-60*72/stored[1])<0.000002
def package(name,format,extra=None,body=None,content_types=None):
    path=directory/(name+'.'+format)
    part='word/document.xml' if format=='docx' else 'ppt/presentation.xml'
    main='<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:rPr><w:rFonts w:ascii="DejaVu Sans"/></w:rPr><w:t>12345</w:t></w:r></w:p></w:body></w:document>' if format=='docx' else '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>'
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as package:
        package.writestr('[Content_Types].xml',content_types if content_types is not None else '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/'+part+'" ContentType="application/vnd.openxmlformats-officedocument.'+('wordprocessingml.document' if format=='docx' else 'presentationml.presentation')+'.main+xml"/></Types>')
        package.writestr(part,body or main)
        if format=='pptx':package.writestr('ppt/slides/slide1.xml','<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>')
        for key,value in (extra or {}).items():package.writestr(key,value)
    return path
for format in ['docx','pptx']:
    path=package('basic',format)
    call(format,path)
    output=directory/('inspection-must-not-convert-'+format+'.pdf')
    result=subprocess.run([str(args.cli.resolve()),format,str(path),str(output)],capture_output=True,text=True)
    assert result.returncode==99,(format,'Office inspection accepted an output path and reported conversion success',result.stdout)
    assert not output.exists()
    cases.append({'name':format+' inspection rejects conversion arguments','expectedExit':99,'passed':True})
picture_body='<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body><w:p><w:r><w:t>Text 123 中文</w:t><w:drawing><a:blip/></w:drawing></w:r></w:p></w:body></w:document>'
for name in ['RGB.png','RGBA.png']:
    call('docx',package('picture-'+Path(name).stem,'docx',{'word/media/image.png':(directory/name).read_bytes()},body=picture_body))
jpeg=directory/'office-photo.jpg';source.convert('RGB').save(jpeg)
call('docx',package('picture-jpeg','docx',{'word/media/image.jpg':jpeg.read_bytes()},body=picture_body))
progressive=directory/'office-progressive.jpg';source.convert('RGB').save(progressive,progressive=True)
call('docx',package('picture-progressive','docx',{'word/media/image.jpg':progressive.read_bytes()},body=picture_body))
call('docx',package('broken-png','docx',{'word/media/image.png':corrupted.read_bytes()},body=picture_body),5)
call('docx',package('broken-jpeg','docx',{'word/media/image.jpg':jpeg.read_bytes()[:-10]},body=picture_body),5)
call('docx',package('unknown-picture','docx',{'word/media/image.wmf':b'unknown graphic'},body=picture_body),17)
private=package('private-glyph','docx',body=picture_body.replace('Text 123 中文','\ue001'))
call('docx',private)
result=subprocess.run([str(args.cli.resolve()),'docx',str(private)],capture_output=True,text=True,check=True)
assert 'characters=1 images=0 private=1' in result.stdout
call('docx',package('empty-content-types','docx',content_types='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'),5)
call('docx',package('wrong-namespace','docx',body='<w:document xmlns:w="urn:wrong"><w:body/></w:document>'),5)
call('docx',package('external','docx',{'word/_rels/document.xml.rels':'<Relationships><Relationship TargetMode="External" Target="https://example.com/image.png"/></Relationships>'}),17)
call('docx',package('signed','docx',{'_xmlsignatures/sig1.xml':'<Signature/>'}),11)
call('docx',package('macro','docx',{'word/vbaProject.bin':'x'}),17)
call('docx',package('ole','docx',{'word/embeddings/item.bin':'x'}),17)
call('docx',package('protected','docx',{'word/settings.xml':'<settings><documentProtection/></settings>'}),11)
call('docx',package('entity','docx',{'word/settings.xml':'<!DOCTYPE settings SYSTEM "file:///etc/passwd"><settings/>'}),11)
call('docx',package('traversal','docx',{'../outside.xml':'<x/>'}),5)
call('docx',package('wrong-format','pptx'),5)
encrypted=directory/'encrypted.docx';encrypted.write_bytes(bytes.fromhex('d0cf11e0a1b11ae1')+b'EncryptedPackage');call('docx',encrypted,11)
report={'scope':'native PNG real conversion and independent pypdf/Poppler; JPEG delivery; Office package checks only','passed':len(cases),'cases':cases,
        'officeRuntimeExecution':'requires OHOS arm64 device; not executed','device':'not executed'}
(root/'tests/generated/core-document-engines.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':len(cases),'device':'not executed'}))
