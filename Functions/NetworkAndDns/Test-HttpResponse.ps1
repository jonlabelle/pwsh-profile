function Test-HttpResponse
{
    <#
    .SYNOPSIS
        Tests HTTP/HTTPS endpoints and returns response details.

    .DESCRIPTION
        Sends HTTP requests to specified URLs and returns detailed response information including
        status code, response time, headers, and content length. This function provides a focused
        tool for testing web services and APIs across all platforms.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Uri
        The URL(s) to test. Supports both HTTP and HTTPS protocols.
        Accepts pipeline input for testing multiple endpoints.

    .PARAMETER Method
        The HTTP method to use for the request.
        Valid values: GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH
        Default is GET.

    .PARAMETER Timeout
        Request timeout in seconds. Default is 30 seconds.
        Valid range: 1-300 seconds (5 minutes).

    .PARAMETER Headers
        Custom HTTP headers to include in the request.
        Provide as a hashtable (e.g., @{ 'Authorization' = 'Bearer token' }).

    .PARAMETER Body
        Request body content for POST, PUT, or PATCH requests.
        Can be a string or object (will be converted to JSON for objects).

    .PARAMETER ContentType
        The Content-Type header value for the request.
        Common values: 'application/json', 'application/xml', 'text/plain'
        Default is 'application/json' when Body is provided.

    .PARAMETER DisableRedirects
        Disable automatic following of HTTP redirects.
        By default, redirects are followed automatically.

    .PARAMETER IncludeHeaders
        Include response headers in the output.
        By default, only basic response information is returned.

    .PARAMETER UserAgent
        Custom User-Agent string for the request.
        Default is "PowerShell/<version>".

    .EXAMPLE
        PS > Test-HttpResponse -Uri 'https://jonlabelle.com'

        Uri               : https://jonlabelle.com
        StatusCode        : 200
        StatusDescription : OK
        Success           : True
        ResponseTime      : 00:00:00.2376194
        ResponseTimeMs    : 237
        ContentLength     : 4601
        ContentType       : text/html; charset=UTF-8

        Tests Google's homepage and returns status code and response time.

    .EXAMPLE
        PS > Test-HttpResponse -Uri 'https://api.github.com/users/octocat' -IncludeHeaders

        Uri               : https://www.google.com
        StatusCode        : 200
        StatusDescription : OK
        Success           : True
        ResponseTime      : 00:00:00.2473482
        ResponseTimeMs    : 247
        ContentLength     : 17741
        ContentType       : text/html; charset=ISO-8859-1
        Headers           : {[Vary, Accept-Encoding], [X-Frame-Options, SAMEORIGIN], [Cache-Control, max-age=0, private], [Accept-CH,
                            Sec-CH-Prefers-Color-Scheme]...}

        Tests GitHub API endpoint and includes response headers.

    .EXAMPLE
        PS > @('https://google.com', 'https://github.com', 'https://stackoverflow.com') | Test-HttpResponse

        Tests multiple URLs using pipeline input.

    .EXAMPLE
        PS > Test-HttpResponse -Uri 'https://httpbin.org/status/404'

        Uri               : https://httpbin.org/status/404
        StatusCode        : 404
        StatusDescription : NOT FOUND
        Success           : False
        ResponseTime      : 00:00:01.4854014
        ResponseTimeMs    : 1485
        ContentLength     :
        ContentType       : text/html; charset=utf-8

        Tests an endpoint that returns a 404 status code.

    .EXAMPLE
        PS > Test-HttpResponse -Uri 'https://api.example.com/data' -Method POST -Body '{"key":"value"}' -Headers @{ 'Authorization' = 'Bearer token123' }

        Sends a POST request with JSON body and custom authorization header.

    .EXAMPLE
        PS > Test-HttpResponse -Uri 'https://slow-endpoint.com' -Timeout 5

        Tests an endpoint with a 5-second timeout.

    .EXAMPLE
        PS > Test-HttpResponse -Uri 'https://httpbin.org/get' -Method GET -IncludeHeaders -Verbose

        Tests with verbose output showing detailed request/response information.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with Uri, StatusCode, StatusDescription, ResponseTime, ContentLength, and optionally Headers.

    .LINK
        https://docs.microsoft.com/en-us/dotnet/api/system.net.http.httpclient

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/NetworkAndDns/Test-HttpResponse.ps1
        Date: November 9, 2025
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Url', 'Endpoint')]
        [String[]]$Uri,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS', 'PATCH')]
        [String]$Method = 'GET',

        [Parameter()]
        [ValidateRange(1, 300)]
        [Int32]$Timeout = 30,

        [Parameter()]
        [Hashtable]$Headers,

        [Parameter()]
        [Object]$Body,

        [Parameter()]
        [String]$ContentType = 'application/json',

        [Parameter()]
        [Switch]$DisableRedirects,

        [Parameter()]
        [Switch]$IncludeHeaders, [Parameter()]
        [String]$UserAgent
    )

    begin
    {
        Write-Verbose 'Initializing HTTP client'

        # Create HTTP client handler
        $httpHandler = [System.Net.Http.HttpClientHandler]::new()
        $httpHandler.AllowAutoRedirect = -not $DisableRedirects.IsPresent

        # Create HTTP client with timeout
        $httpClient = [System.Net.Http.HttpClient]::new($httpHandler)
        $httpClient.Timeout = [TimeSpan]::FromSeconds($Timeout)

        # Set User-Agent
        if ($UserAgent)
        {
            $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd($UserAgent)
        }
        else
        {
            $psVersion = $PSVersionTable.PSVersion.ToString()
            $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShell/$psVersion")
        }
    }

    process
    {
        foreach ($url in $Uri)
        {
            Write-Verbose "Testing URI: $url with method: $Method"

            try
            {
                # Validate URI format
                $uriObject = $null
                if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$uriObject))
                {
                    Write-Error "Invalid URI format: $url"
                    continue
                }

                # Create HTTP request message
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::$Method, $uriObject)

                # Add custom headers
                if ($Headers)
                {
                    foreach ($key in $Headers.Keys)
                    {
                        Write-Verbose "Adding header: $key"
                        $request.Headers.TryAddWithoutValidation($key, $Headers[$key]) | Out-Null
                    }
                }

                # Add body for applicable methods
                if ($Body -and ($Method -in @('POST', 'PUT', 'PATCH')))
                {
                    Write-Verbose 'Adding request body'

                    # Convert object to JSON if needed
                    if ($Body -is [String])
                    {
                        $bodyContent = $Body
                    }
                    else
                    {
                        $bodyContent = $Body | ConvertTo-Json -Depth 10
                    }

                    $request.Content = New-Object System.Net.Http.StringContent($bodyContent, [System.Text.Encoding]::UTF8, $ContentType)
                }

                # Send request and measure response time
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $response = $httpClient.SendAsync($request).GetAwaiter().GetResult()
                $stopwatch.Stop()

                Write-Verbose "Response received: $($response.StatusCode) in $($stopwatch.ElapsedMilliseconds)ms"

                # Read content length
                $contentLength = if ($response.Content.Headers.ContentLength)
                {
                    $response.Content.Headers.ContentLength
                }
                else
                {
                    $null
                }

                # Build result object
                $result = [PSCustomObject]@{
                    Uri = $url
                    StatusCode = [int]$response.StatusCode
                    StatusDescription = $response.ReasonPhrase
                    Success = $response.IsSuccessStatusCode
                    ResponseTime = $stopwatch.Elapsed
                    ResponseTimeMs = $stopwatch.ElapsedMilliseconds
                    ContentLength = $contentLength
                    ContentType = if ($response.Content.Headers.ContentType) { $response.Content.Headers.ContentType.ToString() } else { $null }
                }

                # Add headers if requested
                if ($IncludeHeaders)
                {
                    $headerDict = @{}

                    # Add response headers
                    foreach ($header in $response.Headers)
                    {
                        $headerDict[$header.Key] = $header.Value -join ', '
                    }

                    # Add content headers
                    if ($response.Content.Headers)
                    {
                        foreach ($header in $response.Content.Headers)
                        {
                            $headerDict[$header.Key] = $header.Value -join ', '
                        }
                    }

                    $result | Add-Member -NotePropertyName 'Headers' -NotePropertyValue $headerDict
                }

                Write-Output $result

                # Cleanup
                $response.Dispose()
                $request.Dispose()
            }
            catch [System.Net.Http.HttpRequestException]
            {
                Write-Verbose "HTTP request exception for $url : $($_.Exception.Message)"

                # Return error result
                [PSCustomObject]@{
                    Uri = $url
                    StatusCode = 0
                    StatusDescription = 'Request Failed'
                    Success = $false
                    ResponseTime = $null
                    ResponseTimeMs = $null
                    ContentLength = $null
                    ContentType = $null
                    Error = $_.Exception.Message
                }
            }
            catch [System.Threading.Tasks.TaskCanceledException]
            {
                Write-Verbose "Request timeout for $url after $Timeout seconds"

                # Return timeout result
                [PSCustomObject]@{
                    Uri = $url
                    StatusCode = 0
                    StatusDescription = 'Timeout'
                    Success = $false
                    ResponseTime = $null
                    ResponseTimeMs = $null
                    ContentLength = $null
                    ContentType = $null
                    Error = "Request timed out after $Timeout seconds"
                }
            }
            catch
            {
                Write-Verbose "Unexpected error for $url : $($_.Exception.Message)"

                # Return general error result
                [PSCustomObject]@{
                    Uri = $url
                    StatusCode = 0
                    StatusDescription = 'Error'
                    Success = $false
                    ResponseTime = $null
                    ResponseTimeMs = $null
                    ContentLength = $null
                    ContentType = $null
                    Error = $_.Exception.Message
                }
            }
        }
    }

    end
    {
        Write-Verbose 'Cleaning up HTTP client'

        if ($httpClient)
        {
            $httpClient.Dispose()
        }
        if ($httpHandler)
        {
            $httpHandler.Dispose()
        }
    }
}
