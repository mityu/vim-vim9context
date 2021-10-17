let g:vim9context#CONTEXT_VIM_SCRIPT  = 0
let g:vim9context#CONTEXT_VIM9_SCRIPT = 1
let g:vim9context#CONTEXT_UNKNOWN     = 2

function! vim9context#get_context() abort
  return vim9context#get_context_pos(line('.'), col('.'))
endfunction

function! vim9context#get_context_pos(linenr, columnnr) abort
  " First, check if there're modifiers that specify script type.
  let context = s:determine_context_by_line(a:linenr, a:columnnr)
  if context != g:vim9context#CONTEXT_UNKNOWN
    return context
  endif

  " Second, check if the line is in a function/vim9script-block.
  let context = s:determine_context_by_blocks(a:linenr, a:columnnr)
  if context != g:vim9context#CONTEXT_UNKNOWN
    return context
  endif

  " Finally, check if there's :vim9script command because when the line does
  " not meet the conditions above, the line is at script level.
  let context = s:determine_context_by_file(a:linenr)
  if context == g:vim9context#CONTEXT_UNKNOWN
    echoerr '[vim9context] Internal Error: context is still unknown at the end.'
    let context = g:vim9context#CONTEXT_VIM_SCRIPT
  endif
  return context
endfunction


" s:determine_context_by_line()
" Determine if the context of the given position is vim9script or not by
" checking command-modifiers.
function! s:determine_context_by_line(linenr, columnnr) abort
  "        vimscript
  " unknown   |      vim9script
  "    |      |          |
  "    v      v          v
  " <-----><------><----------->
  " :legacy vim9cmd echo 'Hello'
  let components = split(s:getline_before_column(a:linenr, a:columnnr))
  let context = g:vim9context#CONTEXT_UNKNOWN
  for c in components
    if c =~# '^\<leg\%[acy]\>$'
      let context = g:vim9context#CONTEXT_VIM_SCRIPT
    elseif c =~# '^\<vim9\%[cmd]\>$'
      let context = g:vim9context#CONTEXT_VIM9_SCRIPT
    elseif c =~# '^\<fu\%[nction]\>!\?$'
      return g:vim9context#CONTEXT_VIM_SCRIPT
    elseif c =~# '^\<def\>!\?$'
      return g:vim9context#CONTEXT_VIM9_SCRIPT
    elseif c =~# '^\<export\>$'
      continue
    else
      break
    endif
  endfor
  return context
endfunction

" s:determine_context_by_blocks()
" Determine if the context of the given position is vim9script or not by
" checking if the given position is contained in any of legacy function, def
" function, and vim9script block.
function! s:determine_context_by_blocks(linenr, columnnr) abort
  let innermost_def = s:find_innermost_def_function(a:linenr, a:columnnr)

  " In def function, the context is always vim9script.
  if innermost_def != 0
    return g:vim9context#CONTEXT_VIM9_SCRIPT
  endif

  " In legacy function, sometimes the context can be vim9script.
  let innermost_legacy = s:find_innermost_legacy_function(a:linenr, a:columnnr)
  let [linenr, columnnr] = [a:linenr, a:columnnr]
  while 1
    let innermost_commandblock = s:find_innermost_braces_block(linenr, columnnr)
    if innermost_commandblock == 0 || innermost_commandblock < innermost_legacy
      " Any functions cannot appear in vim9script block.
      break
    elseif s:is_vim9script_block_beginning(
          \ innermost_commandblock, col([innermost_commandblock, '$']))
      return g:vim9context#CONTEXT_VIM9_SCRIPT
    elseif innermost_commandblock == 1
      " There's no outer block anymore.
      break
    endif
    let linenr = innermost_commandblock - 1
    let columnnr = col([linenr, '$'])
  endwhile

  if innermost_legacy != 0
    return g:vim9context#CONTEXT_VIM_SCRIPT
  endif
  return g:vim9context#CONTEXT_UNKNOWN
endfunction

" s:is_vim9script_block_beginning()
" Check if the given position is in a vim9script block such as below:
"   <------ unknown ------> <-- vim9script -->
"   :command! GreatCommand {
"     <-- vim9script -->
"   }
"
"   <------ unknown ------> <-- vim9script -->
"   :autocmd Event pattern {
"     <-- vim9script -->
"   }
"
"   (For details, see :h :command-repl)
"
" If the given position is in a vim9script block, returns 1; otherwise,
" returns 0.
function! s:is_vim9script_block_beginning(linenr, columnnr) abort
  let line = s:getline_before_column(a:linenr, a:columnnr)
  let patterns = []

  " Pattern matcher for :command
  call add(patterns, '\v^\s*com%[mand]>!?%(\s+-\S+)*\s+\u\a*\s+\{\s*$')

  " Pattern matcher for :autocmd
  call add(patterns,
  \  '\v^\s*au%[tocmd]>%(\s+\S+){2,3}%(\s+%(\+\+\a+|nested)>)*\s+\{\s*$')

  for p in patterns
    if line =~# p
      return 1
    endif
  endfor
  return 0
endfunction

" s:determine_context_by_file()
" Check if the vim9script use exists above cursor line or not and determine if
" the file is vim9script file or not. This function must not return
" g:vim9context#CONTEXT_UNKNOWN.
function! s:determine_context_by_file(linenr) abort
  let curpos = getpos('.')
  try
    normal! gg0
    let linenr = search('^\s*\<vim9s\%[cript]\>\%(\s\+noclear\)\?\s*$',
          \ 'cnW', a:linenr)
    if linenr <= 0 || linenr == a:linenr
      return g:vim9context#CONTEXT_VIM_SCRIPT
    endif
    return g:vim9context#CONTEXT_VIM9_SCRIPT
  finally
    call setpos('.', curpos)
  endtry
endfunction

function! s:find_innermost_legacy_function(linenr, columnnr) abort
  let begin = '\v^\s*%(<%(export|leg%[acy]|vim9%[cmd])>\s+)*fu%[nction]>'
  let end = '\<en\%[dfunction]\>'
  return s:find_innermost_block(begin, end, a:linenr, a:columnnr)
endfunction

function! s:find_innermost_def_function(linenr, columnnr) abort
  let begin = '\v^\s*%(<%(export|legacy|vim9cmd)>\s+)*def>'
  let end = '\<enddef\>'
  return s:find_innermost_block(begin, end, a:linenr, a:columnnr)
endfunction

function! s:find_innermost_braces_block(linenr, columnnr) abort
  let begin = '\s{\s*$'
  let end = '^\s*}\s*$'
  return s:find_innermost_block(begin, end, a:linenr, a:columnnr)
endfunction

" Search the innermost block and returns the line that the block begins.
" If block is not found, returns 0.
function! s:find_innermost_block(begin, end, linenr, columnnr) abort
  if s:getline_before_column(a:linenr, a:columnnr) =~# a:begin
    return a:linenr
  endif

  let curpos = getpos('.')
  try
    " NOTE: The block end position is special. The context of the whole line
    " of ending block should be same to it of the block:
    "   :endfunction <-- vimscript -->
    "   :enddef <-- vim9script -->
    "   } <-- vim9script -->
    " That's why, if the line matches a:end, make the column of cursor 1 then
    " search pairs.
    if getline(a:linenr) =~# a:end
      call cursor(a:linenr, 1)
    else
      call cursor(a:linenr, a:columnnr)
    endif
    let linenr = searchpair(a:begin, '', a:end, 'bWnz')
    if linenr <= 0
      return 0
    endif
    return linenr
  finally
    call setpos('.', curpos)
  endtry
endfunction


function! s:getline_before_column(linenr, columnnr) abort
  let line = getline(a:linenr)
  if stridx(mode(), 'i') != -1
    let line = strpart(line, 0, a:columnnr - 1)
  else
    let line = strpart(line, 0, a:columnnr)
  endif
  return line
endfunction

