"""
"
" Coypright 2009, 2013-2014 Stefan Goebel.
"
" This program is free software: you can redistribute it and/or modify it under
" the terms of the GNU General Public License as published by the Free Software
" Foundation, either version 3 of the License, or (at your option) any later
" version.
"
" This program is distributed in the hope that it will be useful, but WITHOUT
" ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
" FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
" details.
"
" You should have received a copy of the GNU General Public License along with
" this program. If not, see <http://www.gnu.org/licenses/>.
"
"""

"""
"
" Vimya 0.4 - Execute buffer contents as MEL or Python scripts in Autodesk Maya
"
" Help is available in doc/vimya.txt or from within Vim with :help vimya.
"
"""

if exists ('g:loadedVimya') || &cp || ! has ('python')
    finish
endif
let g:loadedVimya = '0.4'

"""
" Configuration variables:
"""

if ! exists ('g:vimyaPort')
    let g:vimyaPort = 12345
endif

if ! exists ('g:vimyaHost')
    let g:vimyaHost = '127.0.0.1'
endif

if ! exists ('g:vimyaDefaultFiletype')
    let g:vimyaDefaultFiletype = 'python'
endif

if ! exists ('g:vimyaShowLog')
    let g:vimyaShowLog = 1
endif

if ! exists ('g:vimyaTempDir')
    let g:vimyaTempDir = ''
endif

if ! exists ('g:vimyaTailCommand')
    let g:vimyaTailCommand = 'TabTail'
endif

if ! exists('g:vimyaSplitBelow')
    let g:vimyaSplitBelow = &splitbelow
endif

if ! exists('g:vimyaRefreshWait')
    let g:vimyaRefreshWait = 2.0
endif

if ! exists('g:vimyaForceRefresh')
    let g:vimyaForceRefresh = 1
endif

"""
" Mappings:
"""

if ! hasmapto ('sendBufferToMaya')
    nnoremap <leader>sm :py sendBufferToMaya ()<cr>
    vnoremap <leader>sm :py sendBufferToMaya ()<cr>
    nnoremap <leader>sb :py sendBufferToMaya (True)<cr>
    vnoremap <leader>sb :py sendBufferToMaya (True)<cr>
endif

if ! hasmapto ('vimyaPing')
    nnoremap <leader>sr :py vimyaPing (0)<cr>
    nnoremap <leader>st :py vimyaPing (1)<cr>
    nnoremap <leader>sl :py vimyaPing (2)<cr>
    vnoremap <leader>sr :py vimyaPing (0)<cr>
    vnoremap <leader>st :py vimyaPing (1)<cr>
    vnoremap <leader>sl :py vimyaPing (2)<cr>
endif

"""
" Main stuff (most of it is Python):
"""

let g:vimyaUseTail = 0
if exists ('g:Tail_Loaded')
    let vimyaUseTail = 1
endif

autocmd VimLeavePre * py __vimyaRemoveLog ()

python << EOP

import os
import socket
import tempfile
import vim
import time

logPath   = ''
setLog    = 0
tempFiles = []

# __vimyaRemoveLog ():
#
# If a logfile was written, delete it. Automatically executed when leaving Vim.
# Also, if some of the temporary file are left on disk, we delete them.

def __vimyaRemoveLog ():
    global logPath
    if logPath != '':
        __vimyaCloseLog ()
        try:
            os.unlink (logPath)
        except:
            pass
    for file in tempFiles:
        try:
            os.unlink (file)
        except:
            pass

# __vimyaCloseLog ():
#
# Issues a `cmdFileOutput -closeAll` command to close the log file.

def __vimyaCloseLog ():
    host = vim.eval ('g:vimyaHost')
    port = int (vim.eval ('g:vimyaPort'))
    try:
        connection = socket.socket (socket.AF_INET, socket.SOCK_STREAM)
        connection.settimeout (5)
        connection.connect ((host, port))
        connection.send ("cmdFileOutput -ca;\n")
        connection.close ()
    except:
        return __vimyaErrorMsg ('Could not close the log file.')
    return True

# errorMsg (message = <string>):
#
# Print the error message given by <string> with the appropriate highlighting.
# Returns always False.

def __vimyaErrorMsg (message):
    vim.command ('echohl ErrorMsg')
    vim.command ("echo \"%s\"" % message )
    vim.command ('echohl None')
    return False

# sendBufferToMaya (forceBuffer = False, userCmd = None):
#
# If userCmd is not specified, saves the buffer (or a part of it) to a temp
# file and instructs Maya to source this file. In visual mode only the selected
# lines are used, else the complete buffer. In visual mode, forceBuffer may be
# set to True to force executing the complete buffer. If selection starts (or
# ends) in the middle of a line, the complete line is included! If userCmd is
# specified, this command will be written to the file sourced by Maya, and the
# buffer content will be ignored. Returns False if an error occured, else True.

def sendBufferToMaya (forceBuffer = False, userCmd = None):

    global logPath, setLog, tempFiles

    type        = vim.eval ('&g:ft')
    defaultType = vim.eval ('g:vimyaDefaultFiletype')
    host        = vim.eval ('g:vimyaHost')
    tempDir     = vim.eval ('g:vimyaTempDir')
    tailCommand = vim.eval ('g:vimyaTailCommand')
    port        = int (vim.eval ('g:vimyaPort'))
    tail        = int (vim.eval ('g:vimyaUseTail'))
    showLog     = int (vim.eval ('g:vimyaShowLog'))
    splitbelow  = int (vim.eval ('g:vimyaSplitBelow'))
    wait        = float (vim.eval('g:vimyaRefreshWait'))
    refresh     = int (vim.eval('g:vimyaForceRefresh'))

    if tempDir:
        tempfile.tempdir = tempDir
    else:
        tempfile.tempdir = None

    if type != '' and type != 'python' and type != 'mel':
        return __vimyaErrorMsg (
                "Error: Supported filetypes: 'python', 'mel', None."
            )

    if logPath == '' and tail == 1 and showLog == 1:
        (logHandle, logPath) = tempfile.mkstemp (
                suffix = '.log', prefix = 'vimya.', text = 1
            )
        setLog = 1

    (tmpHandle, tmpPath) = tempfile.mkstemp (
            suffix = '.py', prefix = 'vimya.', text = 1
        )
    tempFiles.append (tmpPath)

    if userCmd:
        os.write (tmpHandle, "%s\n" % userCmd)
    else:
        vStart = vim.current.buffer.mark ('<')
        if (vStart is None) or (forceBuffer):
            for line in vim.current.buffer:
                os.write (tmpHandle, "%s\n" % line)
        else:
            vEnd = vim.current.buffer.mark ('>')
            for line in vim.current.buffer [vStart [0] - 1 : vEnd [0]]:
                os.write (tmpHandle, "%s\n" % line)
    os.close (tmpHandle)

    try:
        connection = socket.socket (socket.AF_INET, socket.SOCK_STREAM)
        connection.settimeout (5)
    except:
        return __vimyaErrorMsg ('Could not create socket.')
    try:
        connection.connect ((host, port))
    except:
        return __vimyaErrorMsg ('Could not connect to the command port.')

    try:
        goback = 0

        if setLog == 1:
            connection.send (
                    "cmdFileOutput -o \"%s\";\n" % logPath.replace ('\\', '/')
                )
            sb = int(vim.eval('&splitbelow'))
            vim.command ("set %ssplitbelow" % ("" if splitbelow else "no"))
            try:
                vim.command ("%s %s" % (tailCommand, logPath))
            finally:
                vim.command ("set %ssplitbelow" % ("" if sb else "no"))
            setLog = 0
            goback = 1 

        connection.send ("commandEcho -state on -lineNumbers on;\n")
        if type == 'python' or (type == '' and defaultType == 'python'):
            connection.send (
                    "python (\"execfile ('%s')\");\n" % \
                        tmpPath.replace ('\\', '/')
                )
        elif (type == 'mel' or (type == '' and defaultType == 'mel')):
            connection.send ("source \"%s\";\n" % tmpPath.replace ('\\', '/'))

        connection.send ("commandEcho -state off -lineNumbers off;\n")
        connection.send (
                "sysFile -delete \"%s\";\n" % tmpPath.replace ('\\', '/')
            )

        if showLog and tail and refresh:
            if goback: 
                vim.command("wincmd p")
            time.sleep(wait)
            __refreshTail()

    except:
        return __vimyaErrorMsg ('Could not send the commands to Maya.')

    try:
        connection.close ()
    except:
        return __vimyaErrorMsg ('Could not close socket.')

    return True


def vimyaPing(opt=0):
    ''' wrapper for refresh and reset functions '''
    if opt==1:
        __resetVimyaTail()
    elif opt==2:
        __resetVimyaLog()
    else:
        __refreshTail()


def __refreshTail():
    ''' Refresh the contents of the vimya Tail '''
    tail = int (vim.eval ('g:vimyaUseTail'))
    try:
        vim.command('call tail#Refresh()')
    except:
        if logPath and tail:
            if not setLog:
                __resetVimyaTail()
            else:
                __resetVimyaLog()
        vim.command('call tail#Refresh()')

def __resetVimyaTail():
    ''' if the log file exists make another preview window '''
    tail = int (vim.eval ('g:vimyaUseTail'))
    splitbelow = int(vim.eval('g:vimyaSplitBelow'))
    tailCommand = vim.eval('g:vimyaTailCommand')
    global setLog
    if tail:
        vim.command('pclose')
        sb = int(vim.eval('&splitbelow'))
        vim.command ("set %ssplitbelow" % ("" if splitbelow else "no"))
        try:
            vim.command ("%s %s" % (tailCommand, logPath))
        finally:
            vim.command ("set %ssplitbelow" % ("" if sb else "no"))
        setLog = 0
        vim.command("wincmd p")
        return True
    return False

def __resetVimyaLog():
    ''' Generate new log file and make Maya write there '''
    tail = int (vim.eval ('g:vimyaUseTail'))
    if tail:
        __vimyaRemoveLog()
        vim.command('pclose')
        global logPath, setLog
        logPath=''
        setLog=1
        sendBufferToMaya(userCmd='print "Vimya log file was reset";')
        return True
    return False

EOP
" vim: set et si nofoldenable ft=python sts=4 sw=4 tw=79 ts=4 fenc=utf8 :
