package main

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"net"
	"os"
	"strconv"
	"time"
)

const defaultCameraIP = "192.168.123.10"
const cameraPort = "12345"

func usage() {
	fmt.Fprintln(os.Stderr, "YoloCam S3 direct ePTZ control")
	fmt.Fprintln(os.Stderr, "Usage:")
	fmt.Fprintln(os.Stderr, "  yolocam-s3-zoom.exe <camera-ip> get")
	fmt.Fprintln(os.Stderr, "  yolocam-s3-zoom.exe <camera-ip> set <factor> [centerX] [centerY]")
	fmt.Fprintln(os.Stderr, "  yolocam-s3-zoom.exe <camera-ip> in [step]")
	fmt.Fprintln(os.Stderr, "  yolocam-s3-zoom.exe <camera-ip> out [step]")
	fmt.Fprintln(os.Stderr, "  yolocam-s3-zoom.exe <camera-ip> reset")
	fmt.Fprintln(os.Stderr, "Factor: 1.0 to 4.0. Default step: 0.25.")
}

func putVarint(dst []byte, field byte, v uint64) []byte {
	key := uint64(field) << 3
	for key >= 128 {
		dst = append(dst, byte(key)|0x80)
		key >>= 7
	}
	dst = append(dst, byte(key))
	for v >= 128 {
		dst = append(dst, byte(v)|0x80)
		v >>= 7
	}
	return append(dst, byte(v))
}

func putBytes(dst []byte, field byte, b []byte) []byte {
	key := uint64(field)<<3 | 2
	for key >= 128 {
		dst = append(dst, byte(key)|0x80)
		key >>= 7
	}
	dst = append(dst, byte(key))
	n := uint64(len(b))
	for n >= 128 {
		dst = append(dst, byte(n)|0x80)
		n >>= 7
	}
	dst = append(dst, byte(n))
	return append(dst, b...)
}

func zoomRect(f, cx, cy float64) []byte {
	half := 0.5 / f
	if cx < half {
		cx = half
	}
	if cx > 1-half {
		cx = 1 - half
	}
	if cy < half {
		cy = half
	}
	if cy > 1-half {
		cy = 1 - half
	}
	x1, y1 := float32(cx-half), float32(cy-half)
	x2, y2 := float32(cx+half), float32(cy+half)
	z := make([]byte, 0, 25)
	// fixed32 fields 1..5
	for field, val := range []float32{x1, y1, float32(f), x2, y2} {
		z = append(z, byte((field+1)<<3|5))
		var b [4]byte
		binary.LittleEndian.PutUint32(b[:], math.Float32bits(val))
		z = append(z, b[:]...)
	}
	return z
}

func valueZoom(f, cx, cy float64) []byte {
	// Value.zoom_rect = field 45, length-delimited
	return putBytes(nil, 45, zoomRect(f, cx, cy))
}

func valueInt(v uint64) []byte { return putVarint(nil, 1, v) } // Value.int_value = field 1

func message(typ, seq, prop uint64, value []byte) []byte {
	m := make([]byte, 0, 64)
	m = putVarint(m, 1, typ)
	m = putVarint(m, 2, seq)
	m = putVarint(m, 5, prop)
	if value != nil {
		m = putBytes(m, 6, value)
	}
	return m
}

func frame(payload []byte) []byte {
	// outer: 08 01 00 00 + rest_len LE32; rest_len = 6 + payload + 2
	rest := 6 + len(payload) + 2
	out := make([]byte, 0, 8+rest)
	out = append(out, 0x08, 0x01, 0x00, 0x00)
	var le [4]byte
	binary.LittleEndian.PutUint32(le[:], uint32(rest))
	out = append(out, le[:]...)
	out = append(out, 0xA5)
	var be [4]byte
	binary.BigEndian.PutUint32(be[:], uint32(len(payload)))
	out = append(out, be[:]...)
	var hx byte = 0xA5
	for i := 0; i < 4; i++ {
		hx ^= be[i]
	}
	out = append(out, hx)
	out = append(out, payload...)
	var px byte
	for _, b := range payload {
		px ^= b
	}
	out = append(out, px, 0x5A)
	return out
}

func readFrame(conn net.Conn) ([]byte, error) {
	h := make([]byte, 8)
	if _, e := readFull(conn, h); e != nil {
		return nil, e
	}
	if h[0] != 0x08 || h[4] != 0 || h[5] != 0 || h[6] != 0 || h[7] == 0 { /* tolerate framing variations */
	}
	rest := binary.LittleEndian.Uint32(h[4:8])
	if rest < 8 || rest > 2<<20 {
		return nil, fmt.Errorf("invalid frame length %d", rest)
	}
	b := make([]byte, rest)
	if _, e := readFull(conn, b); e != nil {
		return nil, e
	}
	if b[0] != 0xA5 || b[len(b)-1] != 0x5A {
		return nil, errors.New("invalid YoloCam frame markers")
	}
	n := binary.BigEndian.Uint32(b[1:5])
	if int(n)+8 != len(b) {
		return nil, fmt.Errorf("invalid payload length %d", n)
	}
	return b[6 : 6+n], nil
}
func readFull(c net.Conn, b []byte) (int, error) {
	n := 0
	for n < len(b) {
		k, e := c.Read(b[n:])
		n += k
		if e != nil {
			return n, e
		}
	}
	return n, nil
}

func readVarint(b []byte, i *int) (uint64, error) {
	var v uint64
	for s := uint(0); ; s += 7 {
		if *i >= len(b) || s > 63 {
			return 0, errors.New("bad varint")
		}
		c := b[*i]
		*i++
		v |= uint64(c&127) << s
		if c < 128 {
			return v, nil
		}
	}
}
func skipField(w byte, b []byte, i *int) error {
	switch w {
	case 0:
		_, e := readVarint(b, i)
		return e
	case 1:
		*i += 8
	case 2:
		n, e := readVarint(b, i)
		if e != nil {
			return e
		}
		*i += int(n)
	case 5:
		*i += 4
	default:
		return errors.New("unsupported wire type")
	}
	if *i > len(b) {
		return errors.New("field past end")
	}
	return nil
}

func parseMessage(b []byte) (typ, seq, status, prop uint64, value []byte, err error) {
	i := 0
	for i < len(b) {
		key, e := readVarint(b, &i)
		if e != nil {
			return 0, 0, 0, 0, nil, e
		}
		f, w := key>>3, key&7
		switch f {
		case 1:
			typ, e = readVarint(b, &i)
		case 2:
			seq, e = readVarint(b, &i)
		case 4:
			status, e = readVarint(b, &i)
		case 5:
			prop, e = readVarint(b, &i)
		case 6:
			var n uint64
			n, e = readVarint(b, &i)
			if e == nil {
				if i+int(n) > len(b) {
					e = errors.New("bad value length")
				} else {
					value = b[i : i+int(n)]
					i += int(n)
				}
			}
		default:
			e = skipField(byte(w), b, &i)
		}
		if e != nil {
			return 0, 0, 0, 0, nil, e
		}
	}
	return
}

func parseZoomValue(v []byte) (float64, float64, float64, error) {
	i := 0
	var f, cx1, cy1, cx2, cy2 float32
	for i < len(v) {
		key, e := readVarint(v, &i)
		if e != nil {
			return 0, 0, 0, e
		}
		field, w := key>>3, key&7
		if field == 45 && w == 2 {
			n, e := readVarint(v, &i)
			if e != nil {
				return 0, 0, 0, e
			}
			z := v[i : i+int(n)]
			i += int(n)
			j := 0
			for j < len(z) {
				k, e := readVarint(z, &j)
				if e != nil {
					return 0, 0, 0, e
				}
				ff := k >> 3
				ww := k & 7
				if ww != 5 || j+4 > len(z) {
					return 0, 0, 0, errors.New("bad zoom rect")
				}
				bits := binary.LittleEndian.Uint32(z[j : j+4])
				j += 4
				val := math.Float32frombits(bits)
				switch ff {
				case 1:
					cx1 = val
				case 2:
					cy1 = val
				case 3:
					f = val
				case 4:
					cx2 = val
				case 5:
					cy2 = val
				}
			}
		} else {
			if e := skipField(byte(w), v, &i); e != nil {
				return 0, 0, 0, e
			}
		}
	}
	if f == 0 {
		return 0, 0, 0, errors.New("no zoom rect")
	}
	return float64(f), float64(cx1+cx2) / 2, float64(cy1+cy2) / 2, nil
}

func exchange(ctx context.Context, cameraIP, cmd string, factor, cx, cy float64) (float64, float64, float64, error) {
	localIP := ""
	// Bind to the matching Windows USB-NCM interface when the caller uses one of
	// the known camera IPs. This prevents Windows from choosing the wrong USB NIC.
	switch cameraIP {
	case "192.168.124.10":
		localIP = "192.168.124.11"
	case "192.168.123.10":
		localIP = "192.168.123.11"
	case "192.168.127.10":
		localIP = "192.168.127.11"
	}
	d := net.Dialer{}
	if localIP != "" {
		d.LocalAddr = &net.TCPAddr{IP: net.ParseIP(localIP), Port: 0}
	}
	conn, e := d.DialContext(ctx, "tcp", net.JoinHostPort(cameraIP, cameraPort))
	if e != nil {
		return 0, 0, 0, e
	}
	defer conn.Close()
	// session attach: SET property 215, int_value=1, seq 1
	if _, e = conn.Write(frame(message(2, 1, 215, valueInt(1)))); e != nil {
		return 0, 0, 0, e
	}
	if _, e = readFrame(conn); e != nil {
		return 0, 0, 0, fmt.Errorf("session attach: %w", e)
	}
	seq := uint64(2)
	if cmd == "get" || cmd == "in" || cmd == "out" {
		if _, e = conn.Write(frame(message(1, seq, 117, nil))); e != nil {
			return 0, 0, 0, e
		}
		p, e := readFrame(conn)
		if e != nil {
			return 0, 0, 0, e
		}
		_, _, st, pr, val, e := parseMessage(p)
		if e != nil {
			return 0, 0, 0, e
		}
		if st != 200 {
			return 0, 0, 0, fmt.Errorf("camera status %d", st)
		}
		if pr != 117 {
			return 0, 0, 0, fmt.Errorf("unexpected property %d", pr)
		}
		factor, cx, cy, e = parseZoomValue(val)
		if e != nil {
			return 0, 0, 0, e
		}
		if cmd == "get" {
			return factor, cx, cy, nil
		}
		seq++
		if cmd == "in" {
			factor += factorStep
		} else {
			factor -= factorStep
		}
		if factor < 1 {
			factor = 1
		}
		if factor > 4 {
			factor = 4
		}
	}
	if factor < 1 || factor > 4 {
		return 0, 0, 0, fmt.Errorf("factor %.2f outside 1.0-4.0", factor)
	}
	if _, e = conn.Write(frame(message(2, seq, 117, valueZoom(factor, cx, cy)))); e != nil {
		return 0, 0, 0, e
	}
	p, e := readFrame(conn)
	if e != nil {
		return 0, 0, 0, e
	}
	_, _, st, pr, _, e := parseMessage(p)
	if e != nil {
		return 0, 0, 0, e
	}
	if st != 200 {
		return 0, 0, 0, fmt.Errorf("camera status %d", st)
	}
	if pr != 117 {
		return 0, 0, 0, fmt.Errorf("unexpected property %d", pr)
	}
	return factor, cx, cy, nil
}

var factorStep = 0.25

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	// Backward-compatible form: if the first argument is a command, use the
	// original/default camera IP. New form: <camera-ip> <command> ...
	cameraIP := defaultCameraIP
	arg := 1
	if net.ParseIP(os.Args[1]) != nil {
		cameraIP = os.Args[1]
		arg = 2
	}
	if len(os.Args) <= arg {
		usage()
		os.Exit(2)
	}
	cmd := os.Args[arg]
	arg++

	if net.ParseIP(cameraIP) == nil {
		fmt.Fprintln(os.Stderr, "Invalid camera IP:", cameraIP)
		os.Exit(2)
	}

	if arg < len(os.Args) && (cmd == "in" || cmd == "out") {
		var e error
		factorStep, e = strconv.ParseFloat(os.Args[arg], 64)
		if e != nil || factorStep <= 0 {
			fmt.Fprintln(os.Stderr, "Invalid step")
			os.Exit(2)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var f, cx, cy float64
	var e error
	switch cmd {
	case "get":
		f, cx, cy, e = exchange(ctx, cameraIP, "get", 0, 0.5, 0.5)
	case "reset":
		f, cx, cy, e = exchange(ctx, cameraIP, "set", 1, 0.5, 0.5)
	case "set":
		if arg >= len(os.Args) {
			usage()
			os.Exit(2)
		}
		f, e = strconv.ParseFloat(os.Args[arg], 64)
		if e != nil {
			fmt.Fprintln(os.Stderr, e)
			os.Exit(2)
		}
		arg++
		cx, cy = 0.5, 0.5
		if arg < len(os.Args) {
			cx, e = strconv.ParseFloat(os.Args[arg], 64)
			arg++
		}
		if e == nil && arg < len(os.Args) {
			cy, e = strconv.ParseFloat(os.Args[arg], 64)
		}
		if e == nil {
			f, cx, cy, e = exchange(ctx, cameraIP, "set", f, cx, cy)
		}
	case "in", "out":
		f, cx, cy, e = exchange(ctx, cameraIP, cmd, 0, 0.5, 0.5)
	default:
		usage()
		os.Exit(2)
	}
	if e != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", e)
		os.Exit(1)
	}
	fmt.Printf("%.2f %.3f %.3f\n", f, cx, cy)
}
