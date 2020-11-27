// Copyright (c) 2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by the MIT license distributed with this software.
module vee

import strings

pub enum Movement {
	up
	down
	left
	right
	page_up
	page_down
	home
	end
}

struct Buffer {
	line_break string = '\n'
	tab_width  int = 4
pub mut:
	lines      []string
	cursor     Cursor
	magnet     Magnet
}

pub fn new_buffer() &Buffer {
	mut b := &Buffer{}
	m := Magnet{ buffer: b }
	b.magnet = m
	return b
}

pub fn (b Buffer) flatten(s string) string {
	return s.replace(b.line_break, r'\n').replace('\t', r'\t')
}

pub fn (b Buffer) flat() string {
	return b.flatten(b.raw())
}

pub fn (b Buffer) raw() string {
	return b.lines.join(b.line_break)
}

pub fn (b Buffer) view(from int, to int) View {

	//b.cursor.pos.x = b.magnet.x
	slice := b.cur_slice()
	mut tabs := 0//slice.count('\t')
	mut vx := 0 //slice_tabs * b.tab_width
	for i := 0; i < slice.len; i++ {
		if slice[i] == `\t` {
			vx += b.tab_width
			tabs++
			continue
		}
		vx++
	}
	//l := b.cur_line()
	mut x := vx //0 //b.cursor.pos.x

	/*if slice_tabs > 0 {
		mx := b.magnet.x
		mvx := b.magnet.vx
		if mx != mvx {
			x = mvx
			if x >= l.len {
				x = l.len
			} else {
				x = slice.len
			}
		}
	} else {
		x = b.magnet.x
		if x > l.len {
			x = l.len
		}
	}*/
	mut lines := []string{}
	for i, line in b.lines {
		if i >= from && i <= to {
			lines << line
		}
	}
	raw := lines.join(b.line_break)
	return View{
		raw: raw.replace('\t', strings.repeat(` `, b.tab_width))
		cursor: {
			pos: Position {
				x: x
				y: b.cursor.pos.y
			}
		}
	}
}

pub fn (b Buffer) cur_char() string {
	x, y := b.cursor.xy()
	line := b.line(y)
	if x >= line.len {
		return ''
	}
	return line[x].str()
}

pub fn (b Buffer) cur_slice() string {
	x, y := b.cursor.xy()
	line := b.line(y)
	if x == 0 || x >= line.len {
		return ''
	}
	return line[..x]
}

pub fn (b Buffer) line(y int) string {
	if y < 0 || y >= b.lines.len {
		return ''
	}
	return b.lines[y]
}

pub fn (b Buffer) cur_line() string {
	_, y := b.cursor.xy()
	return b.line(y)
}

pub fn (b Buffer) cur_line_flat() string {
	return b.flatten(b.cur_line())
}

pub fn (b Buffer) cursor_index() int {
	mut i := 0
	for y, line in b.lines {
		if b.cursor.pos.y == y {
			i += b.cursor.pos.x
			break
		}
		i += line.len+1
	}
	return i
}

pub fn (mut b Buffer) put(ipt InputType) {
	s := ipt.str()
	has_line_ending := s.contains(b.line_break)
	x, y := b.cursor.xy()
	if b.lines.len == 0 { b.lines.prepend('') }
	line := b.lines[y]
	l := line[..x]
	r := line[x..]
	if has_line_ending {
		mut lines := s.split(b.line_break)
		lines[0] = l + lines[0]
		lines[lines.len - 1] += r
		b.lines.delete(y)
		b.lines.insert(y, lines)
		last := lines[lines.len - 1]
		b.cursor.set(last.len, y + lines.len - 1)
		if s == b.line_break {
			b.cursor.set(0,b.cursor.pos.y)
		}
	} else {
		b.lines[y] = l + s + r
		b.cursor.set(x + s.len, y)
	}
	b.magnet.record()
	$if debug {
		eprintln(@MOD+'.'+@STRUCT+'::'+@FN+' "${b.flat()}"')
	}
}

pub fn (mut b Buffer) del(amount int) string {
	if amount == 0 { return '' }
	x, y := b.cursor.xy()
	if amount < 0 { // don't delete left if we're at 0,0
		if x == 0 && y == 0 { return '' }
	} else {
		if x >= b.cur_line().len && y >= b.lines.len-1 { return '' }
	}
	mut removed := ''
	//line := b.lines[y]
	if amount < 0 { // backspace (backward)
		i := b.cursor_index()
		removed = b.raw()[i+amount..i]
		mut left := amount * -1
		for li := y; li >= 0 && left > 0; li-- {
			ln := b.lines[li]
			if left > ln.len {
				b.lines.delete(li)
				if ln.len == 0 { // line break delimiter
					left--
					if y == 0 { return '' }
					line_above := b.lines[li-1]
					b.cursor.pos.x = line_above.len
				} else {
					left -= ln.len
				}
				b.cursor.pos.y--
			} else {
				if x == 0 {
					if y == 0 { return '' }
					line_above := b.lines[li-1]
					if ln.len == 0 { // at line break
						b.lines.delete(li)
						b.cursor.pos.y--
						b.cursor.pos.x = line_above.len
					} else {
						b.lines[li-1] = line_above + ln
						b.lines.delete(li)
						b.cursor.pos.y--
						b.cursor.pos.x = line_above.len
					}
				} else if x == 1 {
					b.lines[li] = b.lines[li][left..]
					b.cursor.pos.x = 0
				} else {
					b.lines[li] = ln[..x-left]+ln[x..]
					b.cursor.pos.x -= left
				}
				left = 0
				break
			}
		}
	} else { // delete (forward)
		i := b.cursor_index()+1
		removed = b.raw()[i-amount..i]
		mut left := amount
		for li := y; li >= 0 && left > 0; li++ {
			ln := b.lines[li]
			if x == ln.len { // at line end
				if y + 1 <= b.lines.len {
					b.lines[li] = ln + b.lines[y + 1]
					b.lines.delete(y + 1)
					left--
					b.del(left)
				}
			} else if left > ln.len {
				b.lines.delete(li)
				left -= ln.len
			} else {
				b.lines[li] = ln[..x]+ln[x+left..]
				left = 0
			}
		}
	}
	b.magnet.record()
	$if debug {
		eprintln(@MOD+'.'+@STRUCT+'::'+@FN+' "${b.flat()}"')
	}
	return removed
}

fn (b Buffer) dump() {
	eprintln('$b.cursor.pos\n${b.raw()}')
}

// free will free all buffer memory
fn (mut b Buffer) free() {
	$if debug { eprintln(@MOD+'.'+@STRUCT+'::'+@FN) }
	for line in b.lines {
		line.free()
	}
	unsafe {
		b.lines.free()
	}
}

// set_cursor will set the cursor within the buffer bounds
pub fn (mut b Buffer) set_cursor(x int, y int) {
	b.cursor.set(x, y)
	b.magnet.record()
}

// sync_cursor will sync the cursor position to be within the buffer bounds
fn (mut b Buffer) sync_cursor() {
	x, y := b.cursor.xy()
	line := b.cur_line()
	if x < 0 {
		b.cursor.pos.x = 0
	}
	if x > line.len - 1 {
		b.cursor.pos.x = line.len - 1
	}
	if b.cursor.pos.y < 0 {
		b.cursor.pos.y = 0
	}
	if b.cursor.pos.y > b.lines.len - 1 {
		b.cursor.pos.y = b.lines.len - 1
	}
}

// move_cursor will navigate the cursor within the buffer bounds
pub fn (mut b Buffer) move_cursor(amount int, movement Movement) {
	pos := b.cursor.pos
	match movement {
		.up {
			if pos.y - amount >= 0 {
				b.cursor.move(0, -amount)
				// Check the move
				line := b.cur_line()
				if b.cursor.pos.x > line.len {
					b.cursor.set(line.len, b.cursor.pos.y)
				}
				//b.magnet.activate()
			}
		}
		.down {
			if pos.y + amount < b.lines.len {
				b.cursor.move(0, amount)
				// Check the move
				line := b.cur_line()
				if b.cursor.pos.x > line.len {
					b.cursor.set(line.len, b.cursor.pos.y)
				}
				//b.magnet.activate()
			}
		}
		.left {
			if pos.x - amount >= 0 {
				b.cursor.move(-amount,0)
				b.magnet.record()
			}
		}
		.right {
			if pos.x + amount <= b.cur_line().len {
				b.cursor.move(amount,0)
				b.magnet.record()
			}
		}
		.page_up {
			dlines := imin(b.cursor.pos.y, amount)
			b.cursor.move(0,-dlines)
			//b.magnet.activate()
		}
		.page_down {
			dlines := imin(b.lines.len-1, b.cursor.pos.y + amount) - b.cursor.pos.y
			b.cursor.move(0,dlines)
			//b.magnet.activate()
		}
		.home {
			b.cursor.set(0,b.cursor.pos.y)
			b.magnet.record()
		}
		.end {
			b.cursor.set(b.cur_line().len, b.cursor.pos.y)
			b.magnet.record()
		}
	}
}

pub fn (mut b Buffer) move_to_word(movement Movement) {
	a := if movement == .left { -1 } else { 1 }
	mut line := b.cur_line()
	mut x, mut y := b.cursor.pos.x, b.cursor.pos.y
	if x + a < 0 && y > 0 {
		y--
		line = b.line(b.cursor.pos.y - 1)
		x = line.len
	} else if x + a >= line.len && y + 1 < b.lines.len {
		y++
		line = b.line(b.cursor.pos.y + 1)
		x = 0
	}
	// first, move past all non-`a-zA-Z0-9_` characters
	for x+a >= 0 && x+a < line.len && !(line[x+a].is_letter() || line[x+a].is_digit() || line[x+a] == `_`) { x += a }
	// then, move past all the letters and numbers
	for x+a >= 0 && x+a < line.len &&  (line[x+a].is_letter() || line[x+a].is_digit() || line[x+a] == `_`) { x += a }
	// if the cursor is out of bounds, move it to the next/previous line
	if x + a >= 0 && x + a <= line.len {
		x += a
	} else if a < 0 && y+1 > b.lines.len && y-1 >= 0 {
		y += a
		x = 0
	}
	b.cursor.set(x, y)
	b.magnet.record()
}

fn imax(x int, y int) int {
	return if x < y { y } else { x }
}

fn imin(x int, y int) int {
	return if x < y { x } else { y }
}

struct Position {
pub mut:
	x int
	y int
}

struct Cursor {
pub mut:
	pos Position
}

fn (mut c Cursor) set(x int, y int) {
	c.pos.x = x
	c.pos.y = y
}

fn (mut c Cursor) move(x int, y int) {
	c.pos.x += x
	c.pos.y += y
}

fn (c Cursor) xy() (int, int) {
	return c.pos.x, c.pos.y
}

struct View {
pub:
	raw    string
	cursor Cursor
}

struct Magnet {
mut:
	buffer &Buffer
//	record bool = true
	x  int
}

pub fn (m Magnet) str() string {
	mut s := @MOD+'.Magnet{
	x: $m.x'
	s += '\n}'
	return s
}

// activate will adjust the cursor to as close valuses as the magnet as possible
pub fn (mut m Magnet) activate() {
	if m.x == 0 || isnil(m.buffer) { return }
	mut b := m.buffer
	line := b.cur_line()

/*
	/*
	if b.cursor.pos.x < m.x {

	}*/
	if m.x > line.len - 1 {
		b.cursor.pos.x = line.len-1
	} else {
		if b.cursor.pos.x < m.x {
			b.cursor.pos.x = m.x
		}
		if m.x < line.len - 1 {
			b.cursor.pos.x = m.x
		}
	}
*/
}

// record will record the placement of the cursor
fn (mut m Magnet) record() {
	if /*!m.record ||*/ isnil(m.buffer) { return }
	m.x = m.buffer.cursor.pos.x
}
/*
fn (mut m Magnet) move_offrecord(amount int, movement Movement) {
	if isnil(m.buffer) { return }
	prev_recording_state := m.record
	m.record = false
	m.buffer.move_cursor(amount, movement)
	m.record = prev_recording_state
}*/
