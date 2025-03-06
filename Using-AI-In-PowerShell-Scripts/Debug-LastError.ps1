<#
.SYNOPSIS
This sample script helps to debug the last error that occurred in PowerShell.

.DESCRIPTION
This sample script helps to debug the last error that occurred in PowerShell using Generative AI via Ollama's API.
See the related blog post here: https://peramhe.github.io/posts/Using-AI-In-PowerShell-Scripts/

.EXAMPLE
./Debug-LastError.ps1

.NOTES
Make sure the Ollama API is running locally on port 11434.

Author: Henri Perämäki
Contact: peramhe.github.io

#>

$ErrorActionPreference = "Stop"

Function Invoke-StreamingOllamaCompletion {
    <#
    .SYNOPSIS
    Invokes an asynchronous completion request to the Ollama streaming API.

    .DESCRIPTION
    This function sends an asynchronous HTTP POST request to the Ollama streaming API to generate a completion based on the provided model and prompt. 
    It reads the response stream as it comes in and outputs the response.

    .PARAMETER Model
    The name of the model to use for generating the completion.

    .PARAMETER Prompt
    The prompt to send to the model for generating the completion.

    .EXAMPLE
    Invoke-StreamingOllamaCompletion -Model "phi3.5" -Prompt "Tell me a joke."

    .NOTES
    Make sure the Ollama API is running locally on port 11434.

    Author: Henri Perämäki
    Contact: peramhe.github.io

    #>
    param (
        [string]$Model,
        [string]$Prompt
    )

    try {
        # Define payload
        $Payload = @{
            model = $Model
            prompt = $Prompt
        } | ConvertTo-Json

        # We need to use HttpClient for async calls
        # https://learn.microsoft.com/en-us/dotnet/api/system.net.http.httpclient?view=net-9.0
        $HttpClient = [System.Net.Http.HttpClient]::new()

        # Prepare HTTP request
        $HTTPRequest = [System.Net.Http.HttpRequestMessage]::new("Post", "http://localhost:11434/api/generate")
        $HTTPRequest.Content = [System.Net.Http.StringContent]::new($Payload, [System.Text.Encoding]::UTF8, "application/json")

        # Send the request async and only wait for the headers
        $HTTPResponse = $HttpClient.SendAsync($HTTPRequest, "ResponseHeadersRead").Result

        # Check if the request was successful
        If (!$HTTPResponse.IsSuccessStatusCode) {
            Throw "Error calling Ollama API. Status code: $($HTTPResponse.StatusCode) - $($HTTPResponse.ReasonPhrase)"
        }

        # Read the response stream as it comes in
        $MemoryStream = $HTTPResponse.Content.ReadAsStreamAsync().Result
        $StreamReader = [System.IO.StreamReader]::new($MemoryStream)

        while (!$StreamReader.EndOfStream) {
            $Line = $Response = $null
            $Line = $StreamReader.ReadLine()
            If ($Line) {
                $Response = ($Line | ConvertFrom-Json -ErrorAction SilentlyContinue).Response
                If ($Response) {
                    Write-Host $Response -NoNewLine
                }
            }
            
        }
    } catch {
        Throw $_
    } finally {
        # Clean up
        $StreamReader.Close()
        $HttpClient.CancelPendingRequests()
        $HttpClient.Dispose()
    }
}

# Get the last error
$LastError = $Error[0]

# Throw the error again to get InvocationInfo, if it's missing
If (!$LastError.InvocationInfo) {
    try {
        Throw $LastError
    } catch {
        $LastError = $_
    }
}

# Format prompt
$Prompt = @"
You are an expert in debugging PowerShell errors. Analyze the following PowerShell error message and provide accurate explanation of the error that occured and the most likely cause for it. Only use the information provided! You should also make a list of search terms that can be used to find more information about the error from the internet. Only include maximum three search terms that are the most relevant to this specific PowerShell error. Your response must be divided under two headers and must not contain any additional content: Analysis of the Error and Search Terms for Further Information.

Error message:
$($LastError.Exception.Message)

The part of the code that caused the error was:
$($LastError.InvocationInfo.PositionMessage)
"@

If (![String]::IsNullOrEmpty($LastError.InvocationInfo.ScriptName)) {
    $Prompt += @"
    
The error occurred in the following script:
$(Get-Content $LastError.InvocationInfo.ScriptName)
"@
} else {
    $Prompt += @"
  
    The error occured when running a command in the console.

"@
}

Write-Host "Last error message:"
Write-Host $($LastError.Exception.Message)
Write-Host

# Invoke Ollama to debug the error
Invoke-StreamingOllamaCompletion -Model "phi3.5" -Prompt $Prompt
