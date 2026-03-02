package main

import (
	"bufio"
	"bytes"
	cryptoRand "crypto/rand"
	"fmt"
	"log"
	"math"
	mathRand "math/rand"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

var rng *mathRand.Rand

func GenerateRandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	_, err := cryptoRand.Read(b)
	// Note that err == nil only if we read len(b) bytes.
	if err != nil {
		return nil, err
	}

	return b, nil
}

const defaultPacketSizesFile = "packet_sizes.txt"

type FilePacketSampler struct {
	samples []int
	index   int
}

func NewFilePacketSampler(path string) (*FilePacketSampler, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var samples []int
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		value, convErr := strconv.Atoi(line)
		if convErr != nil {
			return nil, fmt.Errorf("invalid packet size %q: %w", line, convErr)
		}
		if value < 0 {
			value = 0
		}
		samples = append(samples, value)
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	if len(samples) == 0 {
		return nil, fmt.Errorf("no packet sizes found in %s", path)
	}

	return &FilePacketSampler{samples: samples}, nil
}

func (s *FilePacketSampler) Sample() int {
	if len(s.samples) == 0 {
		return 0
	}
	value := s.samples[s.index]
	s.index++
	if s.index >= len(s.samples) {
		s.index = 0
	}
	return value
}

type TruncatedExponential struct {
	lambda float64
	min    float64
	max    float64
	rng    *mathRand.Rand
}

func NewTruncatedExponential(lambda, min, max float64, seed int64) *TruncatedExponential {
	if lambda <= 0 {
		panic("lambda must be positive")
	}
	if min >= max {
		panic("min must be < max")
	}

	src := mathRand.NewSource(seed)

	return &TruncatedExponential{
		lambda: lambda,
		min:    min,
		max:    max,
		rng:    mathRand.New(src),
	}
}

func (t *TruncatedExponential) Sample() float64 {
	u := t.rng.Float64()

	rangeExp := 1 - math.Exp(-t.lambda*(t.max-t.min))

	return t.min - (1/t.lambda)*math.Log(1-u*rangeExp)
}

// packet_total_size only has an effect if bigger than 184
func sendPostRequest(packet_total_size int, dest_url string, sequence_number int) {

	// adjusted_size = total_size - http headers (found with wireshark)
	adjusted_size := packet_total_size - 184
	if adjusted_size < 0 {
		adjusted_size = 0
	}
	body, err := GenerateRandomBytes(adjusted_size)
	if err != nil {
		fmt.Println("Error while generating bytes!")
		log.Fatal(err)
	}
	req, err := http.NewRequest("POST", dest_url, bytes.NewBuffer(body))

	// Add headers for measurement point
	req.Header.Add("exp_id", os.Getenv("EXPID"))
	req.Header.Add("run_id", os.Getenv("RUNID"))
	req.Header.Add("key_id", os.Getenv("KEYID"))
	req.Header.Add("counter", strconv.Itoa(sequence_number))

	if err != nil {
		fmt.Println(err)
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Fatal(err)
	}

	if resp.StatusCode != 200 {
		log.Fatal("Status code not 200!!")
	}

	defer resp.Body.Close()
}

// sendHttpRequests sends `num` POSTs. Packet size and time between
// packets are chosen uniformly between the provided min/max ranges.
// Sizes are interpreted as total packet size.
func sendHttpRequests(num, maxSize, minIntervalMs, maxIntervalMs int, dest_url string) {
	packetSampler, err := NewFilePacketSampler(defaultPacketSizesFile)
	if err != nil {
		log.Fatalf("failed to load packet sizes from %s: %v", defaultPacketSizesFile, err)
	}

	exp := NewTruncatedExponential(
		0.01, // Exponential mean formula: mean_ms = 1/λ  =>  λ = 1/mean_ms (target mean ≈ 100 ms)
		float64(minIntervalMs),
		float64(maxIntervalMs),
		time.Now().UnixNano(),
	)

	var wg sync.WaitGroup
	for i := 0; i < num; i++ {
		size := min(packetSampler.Sample(), maxSize) // Limit max size so request does not split into multiple packets

		wg.Add(1)
		go func(seq int, s int) {
			defer wg.Done()
			sendPostRequest(s, dest_url, seq)
		}(i, size)

		if i < num-1 {
			// sleep a uniformly-chosen interval (milliseconds)
			// interval := randIntInclusive(minIntervalMs, maxIntervalMs)
			interval := exp.Sample()
			if interval > 0 {
				time.Sleep(time.Duration(interval) * time.Millisecond)
			}
		}
	}
	wg.Wait()
}

func printPacketSizes() {
	packetSampler, err := NewFilePacketSampler(defaultPacketSizesFile)
	if err != nil {
		log.Fatalf("failed to load packet sizes from %s: %v", defaultPacketSizesFile, err)
	}

	for i := 1; i < 1000; i++ {
		fmt.Println(packetSampler.Sample())
	}
	os.Exit(0)
}

func main() {
	printPacketSizes()
	argsWithoutProg := os.Args[1:]

	// Get packet count
	if len(argsWithoutProg) < 1 {
		log.Fatal("usage: httptrafficgenerator <packet_count> <max_size> <min_interval_ms> <max_interval_ms> dest_url")
	}

	packet_count, err := strconv.Atoi(argsWithoutProg[0])
	if err != nil {
		log.Fatal(err)
	}

	// Defaults: keep previous behavior if optional args not provided.
	maxSize := 200
	minIntervalMs, maxIntervalMs := 0, 0

	if len(argsWithoutProg) >= 4 {
		if v, e := strconv.Atoi(argsWithoutProg[1]); e == nil {
			maxSize = v
		}
		if v, e := strconv.Atoi(argsWithoutProg[2]); e == nil {
			minIntervalMs = v
		}
		if v, e := strconv.Atoi(argsWithoutProg[3]); e == nil {
			maxIntervalMs = v
		}
	}

	dest_url := argsWithoutProg[4]
	if dest_url == "" {
		log.Fatal("dest_url must not be empty")
	}

	if maxSize < 0 {
		log.Fatal("sizes can't be less than 0")
	}

	if minIntervalMs > maxIntervalMs {
		log.Fatal("minInterval can't be bigger than maxInterval")
	}

	if minIntervalMs < 0 || maxIntervalMs < 0 {
		log.Fatal("interval can't be less than 0")
	}

	rng = mathRand.New(mathRand.NewSource(time.Now().UnixNano()))

	sendHttpRequests(packet_count, maxSize, minIntervalMs, maxIntervalMs, dest_url)

	os.Exit(0)
}
