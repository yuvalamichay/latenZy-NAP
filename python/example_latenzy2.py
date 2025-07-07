# -*- coding: utf-8 -*-
"""
example_latenzy2

Example code using the latenzy2 function to compute the onset of a difference
between two spiking responses.

2025, Alexander Heimel, Robin Haak
"""

import numpy as np
import scipy.io as sio
import os
from latenzy import latenzy2
from dependencies import (my_randperm)


np.random.seed(1)

data_path = os.path.dirname(os.path.dirname(__file__))
mat_data = sio.loadmat(os.path.join(data_path, 'example_data', 'Topo2_20220126_AP.mat'), struct_as_record=False, squeeze_me=True)
sAP = mat_data['sAP']
clusters = sAP.sCluster
is_good = np.array([c.KilosortGood for c in clusters])
low_contam = np.array([c.Contamination for c in clusters]) < 0.1
in_primary_visual = np.array(['primary visual' in c.Area.lower() for c in clusters])
idx_incl = (is_good | low_contam) & in_primary_visual
spike_times_agg = [c.SpikeTimes for i, c in enumerate(clusters) if idx_incl[i]]
 
sel_clus = [16, 19, 20]
sel_clus = [i-1 for i in sel_clus] # MATLAB indexing to Python
sBlock = sAP.cellBlock[3]
event_times = sBlock.vecStimOnTime
 
# Create two conditions
n = len(event_times)
# idx = np.random.permutation(n)
idx = my_randperm(n,n)
event_times1 = np.sort(event_times[idx[:n // 2]])
event_times2 = np.sort(event_times[idx[n // 2:]])
 
# Modify spike times for event_times2
diff_latency = 0.1
for i in sel_clus:
    spikes = spike_times_agg[i].copy()
    for j in range(len(event_times1)):
        in_window = np.where((spikes > (event_times1[j] + diff_latency)) &
                             (spikes < (event_times1[j] + diff_latency + 0.1)))[0]
        if in_window.size > 0:
            n_select = int(np.ceil(in_window.size * 0.25))
            if n_select > 0:
                selected = my_randperm(in_window.size, n_select)
                new_spikes = spikes[in_window[selected]] - event_times1[j] + event_times2[j]
                spikes = np.delete(spikes, in_window[selected])
                spikes = np.sort(np.concatenate((spikes, new_spikes)))
    spike_times_agg[i] = spikes
 
result,s_latenzy2 = latenzy2(spike_times_agg[sel_clus[0]], event_times2,
                          spike_times_agg[sel_clus[0]], event_times1, 
                          use_dur=1.,resamp_num=250,peak_alpha=0.05,
                          use_par_pool=False,use_direct_quant=False,
                          restrict_neg=True,make_plots=1)
print(result)
print(s_latenzy2)



