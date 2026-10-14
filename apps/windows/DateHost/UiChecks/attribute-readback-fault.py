import os,sys,subprocess
from pathlib import Path
args=sys.stdin.buffer.read().replace(b'\r\n',b'\n')
target=Path(os.environ['PHOTOTRAIL_R04C_FAULT_TARGET'])
marker=Path(os.environ['PHOTOTRAIL_R04C_FAULT_MARKER'])
if not marker.exists() and str(target).encode('utf-8') in args and b'-j\n' in args and target.exists() and abs(target.stat().st_mtime-1672531200)<0.000001:
 os.utime(target,ns=(target.stat().st_atime_ns,1672531210000000000))
 marker.write_text('Owned synthetic target: postcommit attribute readback mismatch injected.\n',encoding='utf-8')
r=subprocess.run([os.environ['PHOTOTRAIL_EXIFTOOL'],'-@','-'],input=args,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr);sys.exit(r.returncode)
