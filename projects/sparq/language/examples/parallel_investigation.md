# Parallel Investigation Example

This example demonstrates how multiple characters can work together to investigate and solve a user's technical issue, using Sparq's concurrency and input handling features.

## The Investigation Scene

```sparq
scene TechnicalInvestigation do
  @title "Multi-Character Technical Investigation"
  @characters [TechnicalGuide, DevOpsGuide, SecurityGuide]
  
  beat :start do
    speak TechnicalGuide, "Hello! I'll help coordinate our investigation."
    
    response = ask UserCharacter, "What seems to be the issue?"
    
    listen response do
      when match("* error * api *") do
        speak TechnicalGuide, "I see there's an API issue. We'll investigate from multiple angles."
        transition :investigate_api
      end
      
      when match("* slow * performance *") do
        speak TechnicalGuide, "Performance issues can be tricky. Let's analyze this thoroughly."
        transition :investigate_performance
      end
      
      when match("* security * concern *") do
        speak TechnicalGuide, "Security is our top priority. We'll look into this right away."
        transition :investigate_security
      end
      
      # Default fallback
      speak TechnicalGuide, "Let me get our team to investigate this."
      transition :general_investigation
    end
  end
  
  beat :investigate_api do
    speak TechnicalGuide, "We'll check the API from multiple perspectives."
    
    parallel do
      direct TechnicalGuide, :analyze_logs, component: "api", async: true
      direct DevOpsGuide, :check_infrastructure, service: "api", async: true
      direct SecurityGuide, :audit_requests, endpoint: "api", async: true
    end
    
    speak TechnicalGuide, "Analysis in progress. This won't take long."
    transition :gather_api_results
  end
  
  beat :gather_api_results do
    log_analysis = wait TechnicalGuide
    infra_status = wait DevOpsGuide
    security_audit = wait SecurityGuide
    
    speak TechnicalGuide, "Here's what we found in the logs: #{log_analysis}"
    speak DevOpsGuide, "Infrastructure status: #{infra_status}"
    speak SecurityGuide, "Security audit results: #{security_audit}"
    
    transition :present_solution
  end
end
```

## The Investigation Flows

```sparq
flow AnalyzeLogs do
  @character TechnicalGuide
  @goal "Analyze system logs for errors and patterns"
  
  step :collect_logs do
    when has_recent_logs?() do
      fetch_relevant_logs()
    end
  end
  
  step :analyze_patterns do
    direct DevOpsGuide, :get_baseline_metrics, async: true
    identify_error_patterns()
  end
  
  step :correlate_events do
    metrics = wait DevOpsGuide
    correlate_with_metrics(metrics)
  end
end

flow CheckInfrastructure do
  @character DevOpsGuide
  @goal "Verify infrastructure health and performance"
  
  step :check_health do
    when service_accessible?() do
      collect_health_metrics()
    end
  end
  
  step :analyze_metrics do
    direct TechnicalGuide, :get_error_thresholds, async: true
    analyze_performance_data()
  end
end

flow AuditRequests do
  @character SecurityGuide
  @goal "Audit API requests for security concerns"
  
  step :gather_requests do
    when has_audit_logs?() do
      collect_request_logs()
    end
  end
  
  step :analyze_patterns do
    identify_security_patterns()
  end
end
```

## Investigation Tools

```sparq
tool LogAnalyzer do
  @description "Analyzes system logs for patterns and anomalies"
  @input_type :log_data
  @output_type :analysis_result
  
  def run(logs, context) do
    case analyze_logs(logs) do
      {:ok, patterns} -> {:ok, "Found #{length(patterns)} significant patterns"}
      {:error, reason} -> {:error, "Log analysis failed: #{reason}"}
    end
  end
end

tool MetricsCollector do
  @description "Collects and analyzes system metrics"
  @input_type :metric_query
  @output_type :metric_data
  
  def run(query, context) do
    case collect_metrics(query) do
      {:ok, data} -> {:ok, "Collected #{length(data)} metric points"}
      {:error, reason} -> {:error, "Metric collection failed: #{reason}"}
    end
  end
end

tool SecurityAuditor do
  @description "Audits requests for security concerns"
  @input_type :request_logs
  @output_type :audit_result
  
  def run(requests, context) do
    case audit_requests(requests) do
      {:ok, findings} -> {:ok, "Completed security audit with #{length(findings)} findings"}
      {:error, reason} -> {:error, "Security audit failed: #{reason}"}
    end
  end
end
```

This example demonstrates:
1. Sophisticated input handling with pattern matching
2. Parallel execution of multiple character flows
3. Coordination between characters using async operations
4. Tool usage in a concurrent environment
5. Proper error handling and result aggregation 