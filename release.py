import os
import json
import shutil
info=json.loads(open('info.json').read())
folder=info['name']+'_'+info['version']
try:
    os.mkdir(folder)
except:
    pass
files=['info.json','control.lua','thumbnail.png','changelog.txt']
for file in files:
    shutil.copy(file,os.path.join(folder,file))
try:
    os.system('cmd /k \"C:\\Program Files\\7-Zip\\7zG.exe\" a -tzip ../../mods/'+folder+'.zip '+folder)
except:
    print('zip failed')