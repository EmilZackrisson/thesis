package main

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"net/http"
)

func RandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	_, err := rand.Read(b)
	return b, err
}

func sendPostRequest(size int) {
	url := "http://192.168.1.101:9000"
	body, err := RandomBytes(size)
	if err != nil {
		panic(err)
	}
	_, err = http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		fmt.Println(err)
	}
}

func sendHttpRequests() {

}

func main() {
	fmt.Println("Hello World!")
	sendPostRequest(0)
}
