// Execute in mongosh connected to the Replica Set.
cfg = rs.conf();
print("Current priorities:");
cfg.members.forEach(m => print(m.host + " priority=" + m.priority));
cfg.members[0].priority = 1;
cfg.members[1].priority = 3;
cfg.members[2].priority = 1;
rs.reconfig(cfg);
print("Priority adjusted: member 2 is preferred (priority 3).");
