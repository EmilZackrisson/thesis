package main

import (
	"bufio"
	cryptoRand "crypto/rand"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"log"
	mathRand "math/rand"
	"net"
	"os"
	"strconv"
	"sync"
	"time"
)

var rng *mathRand.Rand

var LOG_INTERVAL = 100

var headerOverhead int
var mode string
var port int

func GenerateRandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	_, err := cryptoRand.Read(b)
	// Note that err == nil only if we read len(b) bytes.
	if err != nil {
		return nil, err
	}

	return b, nil
}

// packet_total_size only has an effect if bigger than 161
// sendRawMessage opens a TCP connection to dest_addr, sends a single
// framed message containing metadata and random padding so that the
// resulting L2 packet size approximates packet_total_size (see headerOverhead).
func sendRawMessage(packet_total_size int, dest_addr string, sequence_number int) {

	if sequence_number%LOG_INTERVAL == 0 {
		log.Printf("Sending the %d:th request to %s", sequence_number, dest_addr)
	}

	// payloadLen is the application payload size (excluding our 4-byte length prefix)
	payloadLen := packet_total_size - headerOverhead - 4
	if payloadLen < 0 {
		payloadLen = 0
	}

	// metadata ascii
	meta := fmt.Sprintf("exp_id=%s;run_id=%s;key_id=%s;counter=%d", os.Getenv("EXPID"), os.Getenv("RUNID"), os.Getenv("KEYID"), sequence_number)
	metaBytes := []byte(meta)

	if len(metaBytes) > payloadLen {
		log.Printf("Warning: metadata length %d exceeds computed payloadLen %d; metadata will be sent but packet will be smaller than requested", len(metaBytes), payloadLen)
	}

	paddingLen := payloadLen - len(metaBytes)
	if paddingLen < 0 {
		paddingLen = 0
	}

	pad, err := GenerateRandomBytes(paddingLen)
	if err != nil {
		log.Fatal(err)
	}

	// build payload: metadata + padding
	payload := make([]byte, 0, len(metaBytes)+len(pad))
	payload = append(payload, metaBytes...)
	payload = append(payload, pad...)

	// open connection per-message
	conn, err := net.Dial("tcp", dest_addr)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	// send framed message: 4-byte big-endian length then payload
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(payload)))
	if _, err := conn.Write(lenBuf[:]); err != nil {
		log.Fatal(err)
	}
	if _, err := conn.Write(payload); err != nil {
		log.Fatal(err)
	}

	// read reply and verify
	var rlenBuf [4]byte
	if _, err := io.ReadFull(conn, rlenBuf[:]); err != nil {
		log.Fatal(err)
	}
	rlen := binary.BigEndian.Uint32(rlenBuf[:])
	if rlen != uint32(len(payload)) {
		log.Printf("Warning: echoed length %d differs from sent %d", rlen, len(payload))
	}
	rbuf := make([]byte, rlen)
	if _, err := io.ReadFull(conn, rbuf); err != nil {
		log.Fatal(err)
	}
	// optional verify exact content
	if !equalSlices(rbuf, payload) {
		log.Printf("Warning: echoed payload differs from sent payload for seq %d", sequence_number)
	}
}

func equalSlices(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func randIntInclusive(min, max int) int {
	if min >= max {
		return min
	}
	return rng.Intn(max-min+1) + min
}

// sendHttpRequests sends `num` POSTs. Packet size and time between
// packets are chosen uniformly between the provided min/max ranges.
// Sizes are interpreted as total packet size.
func sendRawRequests(num, minSize, maxSize, minIntervalMs, maxIntervalMs int, dest_addr string) {
	log.Printf("Sending %d requests to %s with minSize=%d, maxSize=%d, minIntervalMs=%d, maxIntervalMs=%d \n", num, dest_addr, minSize, maxSize, minIntervalMs, maxIntervalMs)
	log.Printf("Will log requests every %d requests\n", LOG_INTERVAL)
	var wg sync.WaitGroup
	for i := 0; i < num; i++ {
		size := randIntInclusive(minSize, maxSize)
		wg.Add(1)
		go func(seq int, s int) {
			defer wg.Done()
			sendRawMessage(s, dest_addr, seq)
		}(i, size)

		if i < num-1 {
			// sleep a uniformly-chosen interval (milliseconds)
			interval := randIntInclusive(minIntervalMs, maxIntervalMs)
			if interval > 0 {
				time.Sleep(time.Duration(interval) * time.Millisecond)
			}
		}
	}
	wg.Wait()
}

func main() {
	// flags
	flag.StringVar(&mode, "mode", "client", "Mode: client or server")
	flag.IntVar(&port, "port", 9000, "Port for server (or destination port for client)")
	flag.IntVar(&headerOverhead, "header-overhead", 54, "Header overhead in bytes (L2+L3+L4) to subtract from packet_total_size")
	flag.Parse()

	args := flag.Args()

	rng = mathRand.New(mathRand.NewSource(time.Now().UnixNano()))

	if mode == "server" {
		addr := fmt.Sprintf(":%d", port)
		log.Printf("Starting server on %s (headerOverhead=%d)", addr, headerOverhead)
		startServer(addr)
		return
	}

	// client mode: accept either:
	// 1) <packet_count> dest_host:port
	// 2) <packet_count> <min_size> <max_size> <min_interval_ms> <max_interval_ms> dest_host:port
	// 3) common shorthand with 5 args: <packet_count> <min_size> <min_interval_ms> <max_interval_ms> dest_host:port
	if len(args) < 2 {
		log.Fatal("usage: tcptrafficgenerator -mode=client <packet_count> [min_size max_size min_interval_ms max_interval_ms] dest_host:port")
	}

	packet_count, err := strconv.Atoi(args[0])
	if err != nil {
		log.Fatal(err)
	}

	// Defaults: keep previous behavior if optional args not provided.
	minSize, maxSize := 200, 200
	minIntervalMs, maxIntervalMs := 0, 0

	// Parse optional arguments in several accepted layouts
	switch len(args) {
	case 2:
		// packet_count, dest
		dest_addr := args[1]
		_ = dest_addr
	case 5:
		// packet_count, minSize, minIntervalMs, maxIntervalMs, dest
		if v, e := strconv.Atoi(args[1]); e == nil {
			minSize = v
			maxSize = v
		}
		if v, e := strconv.Atoi(args[2]); e == nil {
			minIntervalMs = v
		}
		if v, e := strconv.Atoi(args[3]); e == nil {
			maxIntervalMs = v
		}
	default:
		// len >= 6: packet_count, minSize, maxSize, minIntervalMs, maxIntervalMs, dest
		if len(args) >= 6 {
			if v, e := strconv.Atoi(args[1]); e == nil {
				minSize = v
			}
			if v, e := strconv.Atoi(args[2]); e == nil {
				maxSize = v
			}
			if v, e := strconv.Atoi(args[3]); e == nil {
				minIntervalMs = v
			}
			if v, e := strconv.Atoi(args[4]); e == nil {
				maxIntervalMs = v
			}
		}
	}

	dest_addr := args[len(args)-1]
	if dest_addr == "" {
		log.Fatal("dest_addr must not be empty")
	}

	if minSize < 0 || maxSize < 0 {
		log.Fatal("sizes can't be less than 0")
	}

	if minIntervalMs < 0 || maxIntervalMs < 0 {
		log.Fatal("interval can't be less than 0")
	}

	if minIntervalMs > maxIntervalMs {
		log.Fatal("minInterval can't be larger than maxInterval")
	}

	if minSize > maxSize {
		log.Fatal("minSize can't be bigger than maxSize")
	}

	sendRawRequests(packet_count, minSize, maxSize, minIntervalMs, maxIntervalMs, dest_addr)

	os.Exit(0)
}

// startServer listens and handles multiple connections concurrently
func startServer(listenAddr string) {
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatal(err)
	}
	defer ln.Close()

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("Accept error: %v", err)
			continue
		}
		log.Printf("Accepted connection from %s", conn.RemoteAddr())
		go handleConn(conn)
	}
}

func handleConn(conn net.Conn) {
	defer conn.Close()
	remote := conn.RemoteAddr().String()
	log.Printf("HandleConn start for %s", remote)
	reader := bufio.NewReader(conn)
	writer := bufio.NewWriter(conn)

	for {
		var lenBuf [4]byte
		if _, err := io.ReadFull(reader, lenBuf[:]); err != nil {
			if err != io.EOF {
				log.Printf("read length error: %v", err)
			}
			return
		}
		l := binary.BigEndian.Uint32(lenBuf[:])
		log.Printf("%s: received length=%d", remote, l)
		if l == 0 {
			// echo zero-length
			if _, err := writer.Write(lenBuf[:]); err != nil {
				log.Printf("write error: %v", err)
				return
			}
			writer.Flush()
			continue
		}
		buf := make([]byte, l)
		if _, err := io.ReadFull(reader, buf); err != nil {
			log.Printf("read payload error: %v", err)
			return
		}

		// write back length + payload
		if _, err := writer.Write(lenBuf[:]); err != nil {
			log.Printf("write length error: %v", err)
			return
		}
		if _, err := writer.Write(buf); err != nil {
			log.Printf("write payload error: %v", err)
			return
		}
		if err := writer.Flush(); err != nil {
			log.Printf("flush error: %v", err)
			return
		}
	}
}
