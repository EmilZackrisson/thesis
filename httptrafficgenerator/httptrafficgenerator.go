package main

import (
	"bytes"
	cryptoRand "crypto/rand"
	"fmt"
	"log"
	mathRand "math/rand"
	"net/http"
	"os"
	"strconv"
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

// packet_total_size only has an effect if bigger than 184
func sendPostRequest(packet_total_size int) {
	url := "http://10.10.0.141:3002"

	// adjusted_size = total_size - http headers (found with wireshark)
	adjusted_size := packet_total_size - 184
	if adjusted_size < 0 {
		adjusted_size = 0
	}
	body, err := GenerateRandomBytes(adjusted_size)
	if err != nil {
		fmt.Println("Error while generating bytes!")
		panic(err)
	}
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		fmt.Println(err)
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()
}

func randIntInclusive(min, max int) int {
	if min >= max {
		return min
	}
	return rng.Intn(max-min+1) + min
}

// sendHttpRequests sends `num` POSTs. Packet size and time between
// packets are chosen uniformly between the provided min/max ranges.
// Sizes are interpreted as total packet size (headers included like before).
func sendHttpRequests(num, minSize, maxSize, minIntervalMs, maxIntervalMs int) {
	for i := 0; i < num; i++ {
		size := randIntInclusive(minSize, maxSize)
		sendPostRequest(size)

		if i == num-1 {
			break
		}

		// sleep a uniformly-chosen interval (milliseconds)
		interval := randIntInclusive(minIntervalMs, maxIntervalMs)
		if interval > 0 {
			time.Sleep(time.Duration(interval) * time.Millisecond)
		}
	}
}

func main() {
	fmt.Println("Hello World!")
	argsWithoutProg := os.Args[1:]

	// Get packet count
	if len(argsWithoutProg) < 1 {
		log.Fatal("usage: httptrafficgenerator <packet_count> [min_size max_size min_interval_ms max_interval_ms]")
	}

	packet_count, err := strconv.Atoi(argsWithoutProg[0])
	if err != nil {
		log.Fatal(err)
	}

	// Defaults: keep previous behavior if optional args not provided.
	minSize, maxSize := 200, 200
	minIntervalMs, maxIntervalMs := 0, 0

	if len(argsWithoutProg) >= 5 {
		if v, e := strconv.Atoi(argsWithoutProg[1]); e == nil {
			minSize = v
		}
		if v, e := strconv.Atoi(argsWithoutProg[2]); e == nil {
			maxSize = v
		}
		if v, e := strconv.Atoi(argsWithoutProg[3]); e == nil {
			minIntervalMs = v
		}
		if v, e := strconv.Atoi(argsWithoutProg[4]); e == nil {
			maxIntervalMs = v
		}
	}

	// Ensure ranges are sane: swap if needed
	if minSize > maxSize {
		minSize, maxSize = maxSize, minSize
	}
	if minIntervalMs > maxIntervalMs {
		minIntervalMs, maxIntervalMs = maxIntervalMs, minIntervalMs
	}

	// Create a local RNG instead of calling math/rand.Seed (deprecated)
	rng = mathRand.New(mathRand.NewSource(time.Now().UnixNano()))

	sendHttpRequests(packet_count, minSize, maxSize, minIntervalMs, maxIntervalMs)
}
