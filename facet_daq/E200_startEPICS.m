% S. Corde and S. Gessner 3/9/13
function myeDefNumber = E200_startEPICS(param)

sys = 'SYS1';
nRuns_pv = [ 'SIOC:' sys ':ML02:AO500' ];
try
    % Update run count
    lcaPut(nRuns_pv, 1+lcaGet(nRuns_pv));
    nRuns = lcaGetSmart(nRuns_pv);
    if isnan(nRuns)
        put2log(sprintf('Channel access failure for %s',nRuns_pv));
        lcaPut(status_pv,'Sorry, can''t increment run count');
        return;
    end
catch
    put2log('Had a problem trying to increment run count');
    return;
end


myName = sprintf('BUFFACQ %d',nRuns);
% Reserve an eDef number
myeDefNumber = eDefReserve(myName);
if isequal (myeDefNumber, 0)
	put2log('Sorry, failed to get eDef');
	return;
else
    % Get the INCM&EXCM
    if param.event_code == 213
        [incmSet, incmReset, excmSet, excmReset, beamcode] = getINCMEXCM('NDRFACET');
    end
    if param.event_code == 233
        [incmSet, incmReset, excmSet, excmReset, beamcode] = getINCMEXCM('SDRFACET');
    end
	% Set the number of pulses
	eDefParams (myeDefNumber, 1, 2800, incmSet, incmReset, excmSet, excmReset, beamcode);
	% press GO button
	eDefOn (myeDefNumber);
end
    

end