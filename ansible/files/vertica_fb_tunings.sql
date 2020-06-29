select get_config_parameter('AWSStreamingConnectionPercentage');
select set_config_parameter('AWSStreamingConnectionPercentage', 0);
select get_config_parameter('AWSStreamingConnectionPercentage');
select get_config_parameter('UseDepotForReads');
select set_config_parameter('UseDepotForReads',1);
select get_config_parameter('UseDepotForReads');
select get_config_parameter('UseDepotForWrites');
select set_config_parameter('UseDepotForWrites',0);
select get_config_parameter('UseDepotForWrites');
select get_config_parameter('AWSConnectionPoolSize');
select set_config_parameter('AWSConnectionPoolSize', 128);
select get_config_parameter('AWSConnectionPoolSize');

