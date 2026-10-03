"""Start the local helper when Designer loads this project plugin.

Compatible with Designer's embedded Python 2.7. No ping or network wait
runs on Designer's application thread.
"""
import os
import subprocess


def start_monitor():
    plugin_file = globals().get('__file__')
    folder = os.path.dirname(os.path.abspath(plugin_file)) if plugin_file else ''
    if not os.path.isfile(os.path.join(folder, 'Start.ps1')):
        # Designer may register a module from source without setting __file__.
        folder = os.path.join(os.getcwd(), 'plugins', 'Projector-Monitor')
    launcher = os.path.join(folder, 'Start.ps1')
    if not os.path.isfile(launcher):
        raise RuntimeError('Projector Monitor: Start.ps1 is missing beside __init__.py.')
    powershell = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'),
                              'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    with open(os.path.join(folder, 'startup.log'), 'ab') as log:
        subprocess.Popen([powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                          '-WindowStyle', 'Hidden', '-File', launcher],
                         cwd=folder, stdout=log, stderr=log,
                         startupinfo=startup, creationflags=0x08000000)


try:
    start_monitor()
except Exception as error:
    # A helper startup failure must not prevent the Designer project loading.
    print('Projector Monitor automatic startup failed: {0}'.format(error))
