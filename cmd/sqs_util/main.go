// Package main - sqs_util application
package main

// import - import our dependencies
import (
	// "bufio"
	// "encoding/base64"
	"flag"
	"fmt"
	// "io"
	"os"
	// "os/exec"
	"regexp"
	"strconv"
	"strings"
	// "time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
)

// Unit - this application's name
const Unit = "sqs_util"

// verbose - control debug output
var verbose bool

// main - log us in...
func main() {
	var (
		account     string
		region      string
		destination string
		message     string
		verbose     bool
		version     bool
	)

	var empty string
	flag.StringVar(&account, "account", "", "AWS account #. E.g. -account='1234556790123'")
	flag.StringVar(&region, "region", "us-east-1", "AWS region. E.g. -region=us-east-1")
	flag.BoolVar(&verbose, "verbose", false, "be more verbose.....")
	flag.BoolVar(&version, "version", false, "print version and exit")
	flag.StringVar(&destination, "destination", "", "vault-register, consul-register, serviceN-register...")
	flag.StringVar(&message, "message", empty, "-tags 'foo=bar,bar=foo,hello=world'")
	flag.Parse()

	if version == true {
		fmt.Println(versionInfo())
		os.Exit(0)
	}

	debugf("[DEBUG]: using account: %s\n", account)
	if account == "" || len(account) < 12 {
		fmt.Printf("sqs_util: missing or invalid account length: -account='1234556790123', received: '%s'\n", account)
		os.Exit(255)
	}

	debugf("[DEBUG]: using destination(s): %s\n", destination)
	if destination == "" || len(destination) < 3 {
		fmt.Printf("sqs_util: missing or invalid destination(s): -destination='some-fancy-queue..', received: '%s'\n", resources)
		os.Exit(255)
	}

	debugf("[DEBUG]: using region: %s\n", region)

	debugf("[DEBUG]: raw input: %s\n", message)
	for k, v := range m {
		debugf("[DEBUG]: mapped: Key=%s,Value=%s\n", k, v)
	}
	ok, err := Send(account, region, verbose, destination, message)
	if !ok {
		fmt.Printf("[ERROR]: failed to send: %s", err)
		os.Exit(254)
	}
	// success!!!
	os.Exit(0)

}

// Login - login to aws ecr registry
func Send(account, region string, verbose bool, destination string, message string) (ok bool, err error) {

	debugf("[DEBUG]: creating new session...\n")
	svc := sqs.New(session.New(), &aws.Config{Region: aws.String(region)})

	debugf("[DEBUG]: creating message(s) input...\n")
	debugf("[DEBUG]: total message input pair(s): %d\n", len(message))
	params := &sqs.SendMessageInput{
		MessageBody:  aws.String(message),     // Required
		QueueUrl:     aws.String(destination), // Required
		DelaySeconds: aws.Int64(1),
		MessageAttributes: map[string]*sqs.MessageAttributeValue{
			"Key": { // Required
				DataType: aws.String("String"), // Required
				BinaryListValues: [][]byte{
					[]byte("PAYLOAD"), // Required
					// More values...
				},
				BinaryValue: []byte("PAYLOAD"),
				StringListValues: []*string{
					aws.String("String"), // Required
					// More values...
				},
				StringValue: aws.String("String"),
			},
			// More values...
		},
	}
	resp, err := svc.SendMessage(params)
	debugf("[DEBUG]: response: %v\n", resp)

	if err != nil {
		return false, fmt.Errorf("Could not create tags for instance(s): '%s': %s\n", strings.Join(resources, " "), err)
	}

	debugf("Successfully sent message(s) '%s'\n", message)
	return true, nil
}

// helper functions....

// debugf - print to stdout if verbose is enabled....
func debugf(format string, args ...interface{}) {
	if verbose == true {
		fmt.Printf(format, args...)
	}
}

// versionInfo - vendoring version info
func versionInfo() string {
	return fmt.Sprintf("%s v%s.%s (%s)", Unit, Version, VersionPrerelease, GitCommit)
}

// ToMap - Convert options into a go map
func ToMap(data string) map[string]string {
	opts := make(map[string]string)
	if data == "" {
		return opts
	}

	// var sanitized string
	// var err error
	sanitized, err := strconv.Unquote(data)
	if err != nil {
		// fmt.Printf("failed to strip quotes: '%s'\n", err)
		sanitized = data
	}

	re1, err := regexp.Compile(",")
	if err != nil {
		return opts
	}
	pairs := re1.Split(sanitized, -1)
	for _, field := range pairs {
		re2, err := regexp.Compile("=")
		if err != nil {
			return opts
		}
		pair := re2.Split(field, 2)
		key := pair[0]
		var val string
		if len(pair) == 2 {
			cleaned, err := strconv.Unquote(pair[1])
			if err != nil {
				val = pair[1]
			} else {
				val = cleaned
			}
		} else {
			val = ""
		}

		opts[key] = val
	}
	return opts
}

// ToSlice - return a string of space delimited arguments as a []string slice
func ToSlice(data string) (slice []string) {
	if data == "" {
		return slice
	}

	list := strings.Fields(data)
	slice = make([]string, len(list))
	for pos, field := range list {
		slice[pos] = field
	}
	return slice
}