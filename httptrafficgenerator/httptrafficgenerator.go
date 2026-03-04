package main

import (
	"bytes"
	cryptoRand "crypto/rand"
	"fmt"
	"log"
	"math"
	mathRand "math/rand"
	"net/http"
	"os"
	"strconv"
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

// BimodalNormalSampler generates packet sizes like this Python code:
// data1 = np.random.normal(40, 300, 400); data1 = data1[data1 > 0]
// data2 = np.random.normal(1500, 300, 200); data2 = data2[data2 < 1500]
// data = np.concatenate([data1, data2])
//
// It samples from N(40,300) with probability 400/(400+200) and keeps values > 0,
// or from N(1500,300) with probability 200/(400+200) and keeps values < 1500.
type BimodalNormalSampler struct {
	mu1, sigma1  float64
	mu2, sigma2  float64
	weightFirst  float64
	secondMaxCut float64
	rng          *mathRand.Rand
}

func NewBimodalNormalSampler(
	mu1, sigma1 float64,
	mu2, sigma2 float64,
	firstCount, secondCount int,
	secondMaxCut float64,
	seed int64,
) *BimodalNormalSampler {
	if sigma1 <= 0 || sigma2 <= 0 {
		panic("sigma must be positive")
	}
	if firstCount <= 0 || secondCount <= 0 {
		panic("counts must be positive")
	}

	src := mathRand.NewSource(seed)
	weightFirst := float64(firstCount) / float64(firstCount+secondCount)

	return &BimodalNormalSampler{
		mu1:          mu1,
		sigma1:       sigma1,
		mu2:          mu2,
		sigma2:       sigma2,
		weightFirst:  weightFirst,
		secondMaxCut: secondMaxCut,
		rng:          mathRand.New(src),
	}
}

func (b *BimodalNormalSampler) Sample() int {
	for {
		if b.rng.Float64() < b.weightFirst {
			value := b.mu1 + b.sigma1*b.rng.NormFloat64()
			if value > 0 {
				return int(math.Round(value))
			}
			continue
		}

		value := b.mu2 + b.sigma2*b.rng.NormFloat64()
		if value < b.secondMaxCut {
			return int(math.Round(value))
		}
	}
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
	sampler := NewBimodalNormalSampler(
		40,   // normal mean for first mode
		300,  // normal stddev for first mode
		1500, // normal mean for second mode
		300,  // normal stddev for second mode
		400,  // first sample count in Python snippet
		200,  // second sample count in Python snippet
		1500, // keep second mode values < 1500
		time.Now().UnixNano(),
	)

	exp := NewTruncatedExponential(
		0.01, // Exponential mean formula: mean_ms = 1/λ  =>  λ = 1/mean_ms (target mean ≈ 100 ms)
		float64(minIntervalMs),
		float64(maxIntervalMs),
		time.Now().UnixNano(),
	)

	var wg sync.WaitGroup
	for i := 0; i < num; i++ {
		// size := randIntInclusive(minSize, maxSize)
		size := min(sampler.Sample(), maxSize) // Limit max size so request does not split into multiple packets

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

func printSizes() {
	sampler := NewBimodalNormalSampler(
		40,   // normal mean for first mode
		300,  // normal stddev for first mode
		1500, // normal mean for second mode
		300,  // normal stddev for second mode
		400,  // first sample count in Python snippet
		200,  // second sample count in Python snippet
		1500, // keep second mode values < 1500
		time.Now().UnixNano(),
	)

	for i := 0; i < 1000; i++ {
		fmt.Println(sampler.Sample())
	}
	os.Exit(0)
}

func main() {
	printSizes()
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
